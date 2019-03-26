# Copyright (c) 2018 Cloudera, Inc. All rights reserved.

# We have to have a procedure in place to roll the AzureClient secrets in running Clusters.
# The best way to do it is via updating the director's environment information.
# Make sure to install the director package. cloudera-director.
# Usage information:
# ~/repos/thunderhead/tools/azure-scripts$ CLIENT_ID=0743b5bc-8b8a-48e2-9a8f-c5477ddb0b33 \
# CLIENT_SECRET=AQICAHg+q+OBP8UlEa/yu+biAFuU+FLO1SMeMM/0JwggH2RpfwETNFIduW6dn+
# ciAK4Yg9kDAAAAjDCBiQYJKoZIhvcNAQcGoHwwegIBADB1BgkqhkiG9w0BBwEwHgYJYIZIAWUDBAE
# uMBEEDGyMyRBvID/5gqkMxwIBEIBIA8zmG5d0KCvNNnJHLlpl6qQZQBjwcRWlk+YGRZa+udaTrfdh
# 9TR5BpXdXgoExoVNxvetVxzKDxbm/ZLiZus7bkHvCEE2Hn3o python roll_secret.py

import base64
import json
import os

import boto3
from boto3.dynamodb.conditions import Key

from cloudera.director.common.client import ApiClient
from cloudera.director.latest import AuthenticationApi, EnvironmentsApi
from cloudera.director.latest.models import Login

session = boto3.session.Session()
kms = session.client('kms')
dynamodb = boto3.resource('dynamodb', region_name='us-west-2')


def _decrypt_password(encrypted_password):
    binary_data = base64.b64decode(encrypted_password)
    meta = kms.decrypt(CiphertextBlob=binary_data)
    plaintext = meta[u'Plaintext']
    return plaintext.decode()


def _get_list_of_directors():
    table = dynamodb.Table('Clusters')
    response = table.scan(
        FilterExpression=Key('EnvironmentType').eq('AZURE')
    )
    directors = []
    for i in response['Items']:
        directors.append(i['DirectorId'])
    print("list of directors" + str(list(set(directors))))
    return list(set(directors))


def list_nodes(director_id):
    ec2 = boto3.client('ec2', region_name='us-west-2')
    reservation = ec2.describe_instances(
        Filters=[{'Name': 'tag:directorId', 'Values': [director_id]}])
    return reservation


def _get_ip_and_password(director_id):
    instance = list_nodes(director_id)
    assert len(instance['Reservations'][0]['Instances']) == 1
    ip = instance['Reservations'][0]['Instances'][0]['PrivateIpAddress']

    table = dynamodb.Table('Directors')
    response = table.scan(
        FilterExpression=Key('DirectorId').eq(director_id)
    )
    assert len(response['Items']) == 1
    return ip, _decrypt_password(response['Items'][0]['EncryptedApiPassword'])


def _verify_azure_update_environment(ip, password):
    address = "http://%s:7189" % ip
    print(address)
    client = ApiClient(address)
    AuthenticationApi(client).login(Login(username="admin", password=password))
    environments_api = EnvironmentsApi(client)
    list_env = environments_api.list()
    print("env list ->" + str(list_env))
    if list_env:
        for environments in list_env:
            environment_information = environments_api.getRedacted(environments)
            if environment_information.provider.type == 'azure':
                print("Azure Environment: " + environments)
                b = {"subscriptionId":
                         environment_information.provider.config['subscriptionId'],
                     "tenantId":
                         environment_information.provider.config['tenantId']
                     }
                c = {
                     "clientId": CLIENT_ID,
                     "clientSecret": CLIENT_SECRET
                     }
                d = dict(b,**c)
                assert CLIENT_ID == \
                       environment_information.provider.config['clientId']
                print(json.dumps(d))
                environments_api.updateProviderCredentials(environments, (d))


if __name__ == "__main__":
    # The values are obtained from the azureClient.properties file. This is for dev.
    encrypted_client_secret = os.environ['CLIENT_SECRET']
    CLIENT_ID = os.environ['CLIENT_ID']
    if (encrypted_client_secret is None) or (CLIENT_ID is None):
        print("Please set CLIENT_SECRET and CLIENT_ID.")
        exit(1)
    CLIENT_SECRET = _decrypt_password(encrypted_client_secret)
    for i in _get_list_of_directors():
        ip, password = _get_ip_and_password(i)
        _verify_azure_update_environment(ip, password)
