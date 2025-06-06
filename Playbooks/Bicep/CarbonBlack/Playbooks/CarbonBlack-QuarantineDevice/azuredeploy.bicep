metadata title = 'Isolate endpoint - Carbon Black'
metadata description = 'This playbook will quarantine the host in Carbon Black.'
metadata mainSteps = [
  '1. Fetch the device information from Carbon Black'
  '2. Quarantine host'
  '3. Enrich the incident with device information from Carbon Black'
]
metadata prerequisites = [
  '1. CarbonBlack Custom Connector needs to be deployed prior to the deployment of this playbook under the same resource group.'
  '2. Generate an API key. Refer this link [ how to generate the API Key](https://developer.carbonblack.com/reference/carbon-black-cloud/authentication/#creating-an-api-key)'
  '3. [Find Organziation key](https://developer.carbonblack.com/reference/carbon-black-cloud/authentication/#creating-an-api-key)'
]
metadata prerequisitesDeployTemplateFile = '../../CarbonBlackConnector/azuredeploy.json'
metadata lastUpdateTime = '2021-07-28T00:00:00.000Z'
metadata entities = [
  'Host'
]
metadata tags = [
  'Remediation'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'Accenture'
}

@description('Name of the Logic Apps resource to be created')
param PlaybookName string = 'IsolateEndpoint-CarbonBlack'

@description('Name of the custom connector which interacts with Carbon Black')
param CustomConnectorName string = 'CarbonBlackCloudConnector'

@description('CarbonBlack Org Key')
param OrganizationKey string = 'OrganizationKey'
param workspace string

var AzureSentinelConnectionName = 'azuresentinel-${PlaybookName}'
var CarbonBlackConnectionName = 'CarbonBlackCloudConnector-${PlaybookName}'

resource CarbonBlackConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: CarbonBlackConnectionName
  location: resourceGroup().location
  properties: {
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/customApis/${CustomConnectorName}'
    }
  }
}

resource AzureSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: AzureSentinelConnectionName
  location: resourceGroup().location
  kind: 'V1'
  properties: {
    displayName: AzureSentinelConnectionName
    customParameterValues: {}
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}

resource Playbook 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: resourceGroup().location
  tags: {
    'hidden-SentinelTemplateName': 'IsolateEndpoint-CarbonBlack'
    'hidden-SentinelTemplateVersion': '1.0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_Azure_Sentinel_incident_creation_rule_was_triggered_(Private_Preview_only)': {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        'Add_comment_to_incident_(V3)': {
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '<p><strong></strong><strong>@{outputs(\'Compose\')}</strong><strong> &nbsp;</strong><span style="font-size: 16px"><strong>CarbonBlack QuarantineDevice Playbook</strong></span><strong><br>\n<br>\nCarbonBlack QuarantineDevice playbook was triggered and collected the following information from Carbon Black:<br>\n<br>\n</strong><strong>@{body(\'Create_HTML_table_-_Carbon_Black\')}</strong><strong><br>\n<br>\nDevices that were quarantined by this playbook:<br>\n<br>\n</strong><strong>@{body(\'Create_HTML_table_-_Quarantined_devices\')}</strong><strong></strong></p>'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/Incidents/Comment'
          }
        }
        Carbon_black_information: {
          runAfter: {
            Organization_Id: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'CarbonblackInformation'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the devices information returned from carbon black cloud'
        }
        Compose: {
          runAfter: {
            'Create_HTML_table_-_Quarantined_devices': [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '<img src="https://avatars.githubusercontent.com/u/2071378?s=280&v=4" alt="Lamp" width="32" height="32">'
        }
        Condition_to_check_the_devices_that_failed_for_quarantine: {
          actions: {
            Update_incident: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  classification: {
                    ClassificationAndReason: 'True Positive - Suspicious Activity'
                  }
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  severity: '@triggerBody()?[\'object\']?[\'properties\']?[\'severity\']'
                  status: 'Closed'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                  }
                }
                method: 'put'
                path: '/Incidents'
              }
            }
          }
          runAfter: {
            'Add_comment_to_incident_(V3)': [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                equals: [
                  '@length(variables(\'FailedforQuarantine\'))'
                  0
                ]
              }
            ]
          }
          type: 'If'
          description: 'Close the incident if there are no devices that failed for quarantine'
        }
        'Create_HTML_table_-_Carbon_Black': {
          runAfter: {
            For_each_hosts: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            columns: [
              {
                header: 'Devicename'
                value: '@item()?[\'name\']'
              }
              {
                header: 'Quarantined'
                value: '@item()?[\'quarantined\']'
              }
              {
                header: 'Policyname'
                value: '@item()?[\'policy_name\']'
              }
              {
                header: 'PolicyId'
                value: '@item()?[\'policy_id\']'
              }
              {
                header: 'DeviceownerId'
                value: '@item()?[\'device_owner_id\']'
              }
              {
                header: 'DeviceId'
                value: '@item()?[\'id\']'
              }
              {
                header: 'Devicestatus'
                value: '@item()?[\'status\']'
              }
              {
                header: 'Operatingsystem'
                value: '@item()?[\'os\']'
              }
              {
                header: 'OperatingsystemVersion'
                value: '@item()?[\'os_version\']'
              }
              {
                header: 'Organizationname'
                value: '@item()?[\'organization_name\']'
              }
              {
                header: 'Email'
                value: '@item()?[\'email\']'
              }
              {
                header: 'Sensorstates'
                value: '@join(item()?[\'sensor_states\'],\',\')'
              }
              {
                header: 'LastreportedTime'
                value: '@item()?[\'last_reported_time\']'
              }
              {
                header: 'SensorVersion'
                value: '@{item()?[\'sensor_version\']}'
              }
            ]
            format: 'HTML'
            from: '@variables(\'CarbonblackInformation\')'
          }
        }
        'Create_HTML_table_-_Quarantined_devices': {
          runAfter: {
            'Create_HTML_table_-_Carbon_Black': [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            columns: [
              {
                header: 'DeviceId'
                value: '@item()?[\'id\']'
              }
              {
                header: 'Devicename'
                value: '@item()?[\'name\']'
              }
              {
                header: 'Action'
                value: '@item()?[\'Action\']'
              }
            ]
            format: 'HTML'
            from: '@variables(\'ActiontakendDevices\')'
          }
        }
        'Entities_-_Get_Hosts': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/entities/host'
          }
        }
        Failed_for_Quarantine: {
          runAfter: {
            Quarantined_devices: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'FailedforQuarantine'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the devices information that failed for Quarantine'
        }
        For_each_hosts: {
          foreach: '@body(\'Entities_-_Get_Hosts\')?[\'Hosts\']'
          actions: {
            Condition: {
              actions: {
                For_each_results: {
                  foreach: '@body(\'Search_devices_in_your_organization\')?[\'results\']'
                  actions: {
                    Condition_to_check_the_device_is_in_quarantine: {
                      actions: {
                        Condition_to_check_the_success_status_codes: {
                          actions: {
                            Condition_to_check_the_search_devices_returned_the_results: {
                              actions: {
                                For_each_search_results: {
                                  foreach: '@body(\'Search_devices_in_your_organization_based_on_device_name\')?[\'results\']'
                                  actions: {
                                    Append_to_device_information: {
                                      runAfter: {}
                                      type: 'AppendToArrayVariable'
                                      inputs: {
                                        name: 'CarbonblackInformation'
                                        value: '@item()'
                                      }
                                      description: 'Append device information that returned from carbon black'
                                    }
                                  }
                                  runAfter: {}
                                  type: 'Foreach'
                                }
                              }
                              runAfter: {
                                Search_devices_in_your_organization_based_on_device_name: [
                                  'Succeeded'
                                ]
                              }
                              expression: {
                                and: [
                                  {
                                    greater: [
                                      '@body(\'Search_devices_in_your_organization_based_on_device_name\')?[\'num_found\']'
                                      0
                                    ]
                                  }
                                ]
                              }
                              type: 'If'
                            }
                            Search_devices_in_your_organization_based_on_device_name: {
                              runAfter: {
                                'Store_devices_information_-_Quarantined': [
                                  'Succeeded'
                                ]
                              }
                              type: 'ApiConnection'
                              inputs: {
                                body: {
                                  query: 'name : @{items(\'For_each_hosts\')?[\'HostName\']}'
                                }
                                headers: {
                                  'Content-Type': 'application/json'
                                }
                                host: {
                                  connection: {
                                    name: '@parameters(\'$connections\')[\'CarbonBlackCloudConnector\'][\'connectionId\']'
                                  }
                                }
                                method: 'post'
                                path: '/appservices/v6/orgs/@{encodeURIComponent(variables(\'OrganizationKey\'))}/devices/_search'
                              }
                            }
                            'Store_devices_information_-_Quarantined': {
                              runAfter: {}
                              type: 'AppendToArrayVariable'
                              inputs: {
                                name: 'ActiontakendDevices'
                                value: {
                                  Action: 'This device was quarantined successfully'
                                  id: '@items(\'For_each_results\')?[\'id\']'
                                  name: '@items(\'For_each_results\')?[\'name\']'
                                }
                              }
                              description: 'Append each devices that quarantined'
                            }
                          }
                          runAfter: {
                            device_actions: [
                              'Succeeded'
                            ]
                          }
                          else: {
                            actions: {
                              'Append_carbon_black_information_-_device_id_in_Quarantine': {
                                runAfter: {}
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'CarbonblackInformation'
                                  value: '@item()'
                                }
                                description: 'Append device information that returned from carbon black'
                              }
                              Devices_that_Failed_for_quarantined: {
                                runAfter: {
                                  'Append_carbon_black_information_-_device_id_in_Quarantine': [
                                    'Succeeded'
                                  ]
                                }
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'FailedforQuarantine'
                                  value: '@item()'
                                }
                                description: 'Variable to store the devices that failed to set the devices in quarantine'
                              }
                            }
                          }
                          expression: {
                            or: [
                              {
                                equals: [
                                  '@outputs(\'device_actions\')?[\'statusCode\']'
                                  200
                                ]
                              }
                              {
                                equals: [
                                  '@outputs(\'device_actions\')?[\'statusCode\']'
                                  204
                                ]
                              }
                            ]
                          }
                          type: 'If'
                        }
                        device_actions: {
                          runAfter: {}
                          type: 'ApiConnection'
                          inputs: {
                            body: {
                              action_type: 'QUARANTINE'
                              device_id: [
                                '@{items(\'For_each_results\')?[\'id\']}'
                              ]
                              options: {
                                toggle: 'ON'
                              }
                            }
                            headers: {
                              'Content-Type': 'application/json'
                            }
                            host: {
                              connection: {
                                name: '@parameters(\'$connections\')[\'CarbonBlackCloudConnector\'][\'connectionId\']'
                              }
                            }
                            method: 'post'
                            path: '/appservices/v6/orgs/@{encodeURIComponent(variables(\'OrganizationKey\'))}/device_actions'
                          }
                        }
                      }
                      runAfter: {}
                      else: {
                        actions: {
                          Append_to_array_variable: {
                            runAfter: {}
                            type: 'AppendToArrayVariable'
                            inputs: {
                              name: 'CarbonblackInformation'
                              value: '@item()'
                            }
                          }
                          Condition_to_check_the_device_OS: {
                            actions: {
                              'Store_devices_information_-_Linux': {
                                runAfter: {}
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'ActiontakendDevices'
                                  value: {
                                    Action: 'Not supported on devices of OS type Linux'
                                    id: '@items(\'For_each_results\')?[\'id\']'
                                    name: '@items(\'For_each_results\')?[\'name\']'
                                  }
                                }
                                description: 'Quarantined is not supported for Linux OS'
                              }
                            }
                            runAfter: {
                              Append_to_array_variable: [
                                'Succeeded'
                              ]
                            }
                            expression: {
                              and: [
                                {
                                  equals: [
                                    '@toLower(item()?[\'os\'])'
                                    'linux'
                                  ]
                                }
                              ]
                            }
                            type: 'If'
                          }
                        }
                      }
                      expression: {
                        and: [
                          {
                            equals: [
                              '@items(\'For_each_results\')?[\'quarantined\']'
                              false
                            ]
                          }
                          {
                            not: {
                              equals: [
                                '@toLower(item()?[\'os\'])'
                                'linux'
                              ]
                            }
                          }
                        ]
                      }
                      type: 'If'
                    }
                  }
                  runAfter: {}
                  type: 'Foreach'
                }
              }
              runAfter: {
                Search_devices_in_your_organization: [
                  'Succeeded'
                ]
              }
              expression: {
                and: [
                  {
                    greater: [
                      '@body(\'Search_devices_in_your_organization\')?[\'num_found\']'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Search_devices_in_your_organization: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  query: 'name : @{items(\'For_each_hosts\')?[\'HostName\']}'
                }
                headers: {
                  'Content-Type': 'application/json'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'CarbonBlackCloudConnector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/appservices/v6/orgs/@{encodeURIComponent(variables(\'OrganizationKey\'))}/devices/_search'
              }
            }
          }
          runAfter: {
            Failed_for_Quarantine: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
          runtimeConfiguration: {
            concurrency: {
              repetitions: 1
            }
          }
        }
        Organization_Id: {
          runAfter: {
            'Entities_-_Get_Hosts': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'OrganizationKey'
                type: 'string'
                value: OrganizationKey
              }
            ]
          }
          description: 'Pre-configured Organization Id'
        }
        Quarantined_devices: {
          runAfter: {
            Carbon_black_information: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ActiontakendDevices'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the quarantined devices information'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          CarbonBlackCloudConnector: {
            connectionId: CarbonBlackConnection.id
            connectionName: CarbonBlackConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/customApis/${CustomConnectorName}'
          }
          azuresentinel: {
            connectionId: AzureSentinelConnection.id
            connectionName: AzureSentinelConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}
