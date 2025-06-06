metadata title = 'Endpoint take action from Teams - Carbon Black'
metadata description = 'This playbook sends an adaptive card to the SOC Teams channel, lets the analyst decide on action: Quarantine the device or Update the policy. It posts a comment on the incident with the information collected from the Carbon Black and summary of the actions taken, and closes the incident if required.'
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
  'Response from teams'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'Accenture'
}

@description('Name of the Logic Apps resource to be created')
param PlaybookName string = 'EndpointTakeActionFromTeams-CarbonBlack'

@description('Name of the custom connector which interacts with Carbon Black')
param CustomConnectorName string = 'CarbonBlackCloudConnector'

@description('CarbonBlack Org Key')
param OrganizationKey string = 'OrganizationKey'

@description('CarbonBlack PolicyId')
param PolicyId int = 0

@description('GroupId of the Team channel')
param Teams_GroupId string = 'TeamgroupId'

@description('Team ChannelId')
param Teams_ChannelId string = 'TeamChannelId'
param workspace string

var AzureSentinelConnectionName = 'azuresentinel-${PlaybookName}'
var CarbonBlackConnectionName = 'CarbonBlackCloudConnector-${PlaybookName}'
var TeamsConnectionName = 'teamsconnector-${PlaybookName}'

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

resource TeamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: TeamsConnectionName
  location: resourceGroup().location
  properties: {
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/teams'
    }
  }
}

resource Playbook 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: resourceGroup().location
  tags: {
    'hidden-SentinelTemplateName': 'EndpointResponseTeams-CarbonBlack'
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
        Action_information_note: {
          runAfter: {
            Organization_Id: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ActionInfo'
                type: 'string'
              }
            ]
          }
          description: 'Variable to show the note n the adaptive card [ Quarantined , Update_Policy ]'
        }
        Action_summary_to_display_in_the_adaptive_card: {
          runAfter: {
            Action_information_note: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ActionSummary'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the summary of the actions taken for each device'
        }
        Action_taken_on_each_device: {
          runAfter: {
            Adaptive_card_columns_list: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'DeviceActions'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the actions to taken on each device'
        }
        Adaptive_card_body: {
          runAfter: {
            Adaptive_card_columns: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AdaptivecardBody'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the adaptive card body'
        }
        Adaptive_card_columns: {
          runAfter: {
            Action_taken_on_each_device: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AdaptivecardColumns'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Prepare adaptive card columns list to show the devices information returned from carbon black'
        }
        Adaptive_card_columns_list: {
          runAfter: {
            Action_summary_to_display_in_the_adaptive_card: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AdaptivecardColumnsList'
                type: 'object'
                value: {}
              }
            ]
          }
          description: 'Prepare adaptive card columns list to show the devices information returned from carbon black'
        }
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
              message: '<p><strong></strong><strong>@{outputs(\'Compose\')}</strong><strong> &nbsp;</strong><span style="font-size: 16px"><strong>CarbonBlack TakeDeviceActionFromTeams Playbook<br>\n</strong></span><strong><br>\nCarbonBlack TakeDeviceActionFromTeams playbook was triggered and collected the following information from Carbon Black:<br>\n<br>\n</strong><strong>@{body(\'Create_HTML_table_-_Carbon_black_device_information\')}</strong><strong><br>\n<br>\nSummary of Device\'s Action taken :</strong><br>\n<br>\n@{body(\'Create_HTML_table\')}<br>\n<br>\n</p>'
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
        Carbon_black_devices_information: {
          runAfter: {
            Incident_hosts: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'CarbonBlackDeviceInfo'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the each device information returned by carbon black cloud'
        }
        Compose: {
          runAfter: {
            'Create_HTML_table_-_Carbon_black_device_information': [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '<img src="https://avatars.githubusercontent.com/u/2071378?s=280&v=4" alt="Lamp" width="32" height="32">'
        }
        Compose_adaptive_card_body: {
          runAfter: {
            For_each_incident_configuration: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@variables(\'AdaptivecardBody\')'
        }
        Compose_incident_configuration: {
          runAfter: {
            For_each_adaptive_card_columns: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: [
            {
              columns: [
                {
                  items: [
                    {
                      size: 'Small'
                      style: 'Person'
                      type: 'Image'
                      url: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1391/1.0.1391.2130/azuresentinel/icon.png'
                    }
                  ]
                  type: 'Column'
                  width: 'auto'
                }
              ]
              type: 'ColumnSet'
            }
            {
              columns: [
                {
                  items: [
                    {
                      size: 'Medium'
                      text: 'Incident configuration'
                      type: 'TextBlock'
                      weight: 'Bolder'
                      wrap: true
                    }
                  ]
                  type: 'Column'
                  width: 'auto'
                }
              ]
              type: 'ColumnSet'
            }
            {
              text: 'Close Azure Sentinal incident?'
              type: 'TextBlock'
            }
            {
              choices: [
                {
                  isSelected: true
                  title: 'False Positive - Inaccurate Data'
                  value: 'False Positive - Inaccurate Data'
                }
                {
                  isSelected: true
                  title: 'False Positive - Incorrect Alert Logic'
                  value: 'False Positive - Incorrect Alert Logic'
                }
                {
                  title: 'True Positive - Suspicious Activity'
                  value: 'True Positive - Suspicious Activity'
                }
                {
                  title: 'Benign Positive - Suspicious But Expected'
                  value: 'Benign Positive - Suspicious But Expected'
                }
                {
                  title: 'Undetermined'
                  value: 'Undetermined'
                }
              ]
              id: 'incidentStatus'
              style: 'compact'
              type: 'Input.ChoiceSet'
              value: 'Benign Positive - Suspicious But Expected'
            }
            {
              text: 'Change Azure Sentinel Incident Severity?'
              type: 'TextBlock'
            }
            {
              choices: [
                {
                  title: 'High'
                  value: 'High'
                }
                {
                  title: 'Medium'
                  value: 'Medium'
                }
                {
                  title: 'Low'
                  value: 'Low'
                }
                {
                  title: 'Don\'t change'
                  value: 'same'
                }
              ]
              id: 'incidentSeverity'
              style: 'compact'
              type: 'Input.ChoiceSet'
              value: '@{triggerBody()?[\'object\']?[\'properties\']?[\'severity\']}'
            }
          ]
          description: 'Compose incident configuration'
        }
        Compose_product_name: {
          runAfter: {
            Select_alert_product_names: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@body(\'Select_alert_product_names\')?[0]?[\'text\']'
          description: 'compose to select the incident alert product name'
        }
        Condition_to_check_the_summary_action_Ignore_or_Submit: {
          actions: {
            Update_incident: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  classification: {
                    ClassificationAndReason: '@{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\']?[\'incidentStatus\']}'
                  }
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  severity: '@{body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\']?[\'incidentSeverity\']}'
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
                  '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'submitActionId\']'
                  'Submit'
                ]
              }
            ]
          }
          type: 'If'
          description: 'Condition to check the summary action taken from SOC "Ignore" or "Change Incident Configuration"'
        }
        Create_HTML_table: {
          runAfter: {
            For_each_hosts_information: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            columns: [
              {
                header: 'DeviceId'
                value: '@item()?[\'device\']'
              }
              {
                header: 'Action'
                value: '@item()?[\'action\']'
              }
              {
                header: 'StatusCode'
                value: '@item()?[\'statuscode\']'
              }
            ]
            format: 'HTML'
            from: '@variables(\'ActionSummary\')'
          }
        }
        'Create_HTML_table_-_Carbon_black_device_information': {
          runAfter: {
            Select_action_summary: [
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
            from: '@variables(\'CarbonBlackDeviceInfo\')'
          }
        }
        DeviceIds: {
          runAfter: {
            Compose_product_name: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'deviceids'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the device ids information'
        }
        Devices_action_needed: {
          runAfter: {
            Carbon_black_devices_information: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'DevicesActionNeeded'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the devices that needs SOC action'
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
        For_each_Hosts: {
          foreach: '@body(\'Entities_-_Get_Hosts\')?[\'Hosts\']'
          actions: {
            Append_Hosts: {
              runAfter: {
                Search_devices_in_your_organization: [
                  'Succeeded'
                ]
              }
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'Hosts'
                value: '@items(\'For_each_Hosts\')?[\'HostName\']'
              }
              description: 'Append each host name to the Hosts'
            }
            Condition_to_check_the_filter_criteria_returns_records: {
              actions: {
                For_each_results: {
                  foreach: '@body(\'Search_devices_in_your_organization\')?[\'results\']'
                  actions: {
                    Append_adaptive_card_columns: {
                      runAfter: {
                        Condition_to_check_the_device_actions: [
                          'Succeeded'
                        ]
                      }
                      type: 'AppendToArrayVariable'
                      inputs: {
                        name: 'AdaptivecardColumns'
                        value: {
                          columns: [
                            '@variables(\'AdaptivecardColumnsList\')'
                          ]
                          type: 'ColumnSet'
                        }
                      }
                      description: 'Prepare adaptive card columns list'
                    }
                    Append_carbon_black_device_information: {
                      runAfter: {
                        Append_deviceids_information: [
                          'Succeeded'
                        ]
                      }
                      type: 'AppendToArrayVariable'
                      inputs: {
                        name: 'CarbonBlackDeviceInfo'
                        value: '@item()'
                      }
                      description: 'Append each device information returned by carbon black cloud'
                    }
                    Append_deviceids_information: {
                      runAfter: {}
                      type: 'AppendToArrayVariable'
                      inputs: {
                        name: 'deviceids'
                        value: '@items(\'For_each_results\')?[\'id\']'
                      }
                    }
                    Condition__to_check_the_device_is_Quarantined_and_policy_configured: {
                      actions: {
                        Empty_actions_if_the_device_is_in_quarantine_and_assigned_to_predefined_policy: {
                          runAfter: {}
                          type: 'SetVariable'
                          inputs: {
                            name: 'DeviceActions'
                            value: []
                          }
                          description: 'Empty actions if the device is in quarantine and assigned to predefined policy'
                        }
                        Set_action_information: {
                          runAfter: {
                            Empty_actions_if_the_device_is_in_quarantine_and_assigned_to_predefined_policy: [
                              'Succeeded'
                            ]
                          }
                          type: 'SetVariable'
                          inputs: {
                            name: 'ActionInfo'
                            value: 'Note: The device is in qurantine and configured to predefined policy'
                          }
                          description: 'Set action information - The device is in quarantine and configured to predefined policy'
                        }
                      }
                      runAfter: {
                        Append_carbon_black_device_information: [
                          'Succeeded'
                        ]
                      }
                      else: {
                        actions: {
                          Condition_to_check_the_quarantine_and_assigned_to_predefined_policy: {
                            actions: {
                              Append__device_ids_to_array: {
                                runAfter: {
                                  Set_device_actions_Quarantine_and_Update_Policy: [
                                    'Succeeded'
                                  ]
                                }
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'DevicesActionNeeded'
                                  value: '@items(\'For_each_results\')?[\'id\']'
                                }
                              }
                              Set_action_info: {
                                runAfter: {
                                  Append__device_ids_to_array: [
                                    'Succeeded'
                                  ]
                                }
                                type: 'SetVariable'
                                inputs: {
                                  name: 'ActionInfo'
                                  value: ' '
                                }
                              }
                              Set_device_actions_Quarantine_and_Update_Policy: {
                                runAfter: {}
                                type: 'SetVariable'
                                inputs: {
                                  name: 'DeviceActions'
                                  value: [
                                    {
                                      title: 'QUARANTINE'
                                      value: 'QUARANTINE'
                                    }
                                    {
                                      title: 'UPDATE_POLICY'
                                      value: 'UPDATE_POLICY'
                                    }
                                    {
                                      title: 'Ignore'
                                      value: 'Ignore'
                                    }
                                  ]
                                }
                                description: 'Set device actions [ Quarantine , Update_Policy and Ignore ]'
                              }
                            }
                            runAfter: {}
                            else: {
                              actions: {
                                Condition_to_set_the_actions_dynamically: {
                                  actions: {
                                    Append_to_array_device_id: {
                                      runAfter: {
                                        'Set_device_actions_[_Update_Policy,_Ignore_]': [
                                          'Succeeded'
                                        ]
                                      }
                                      type: 'AppendToArrayVariable'
                                      inputs: {
                                        name: 'DevicesActionNeeded'
                                        value: '@items(\'For_each_results\')?[\'id\']'
                                      }
                                    }
                                    'Set_action_information_-_The_device_is_in_quarantine': {
                                      runAfter: {}
                                      type: 'SetVariable'
                                      inputs: {
                                        name: 'ActionInfo'
                                        value: 'Note: The device is in qurantine'
                                      }
                                      description: 'Set action information - The device is in quarantine'
                                    }
                                    'Set_device_actions_[_Update_Policy,_Ignore_]': {
                                      runAfter: {
                                        'Set_action_information_-_The_device_is_in_quarantine': [
                                          'Succeeded'
                                        ]
                                      }
                                      type: 'SetVariable'
                                      inputs: {
                                        name: 'DeviceActions'
                                        value: [
                                          {
                                            title: 'UPDATE_POLICY'
                                            value: 'UPDATE_POLICY'
                                          }
                                          {
                                            title: 'Ignore'
                                            value: 'Ignore'
                                          }
                                        ]
                                      }
                                      description: 'Set device actions [ Update_Policy , Ignore ]'
                                    }
                                  }
                                  runAfter: {}
                                  else: {
                                    actions: {
                                      Condition: {
                                        actions: {
                                          Device_actions__are_not_required: {
                                            runAfter: {
                                              'Set_action_information_-_Quarantine_is_not_supported_on_devices_of_OS_type_Linux': [
                                                'Succeeded'
                                              ]
                                            }
                                            type: 'SetVariable'
                                            inputs: {
                                              name: 'DeviceActions'
                                              value: []
                                            }
                                            description: 'Quarantine  action is not supported on devices of OS type Linux'
                                          }
                                          'Set_action_information_-_Quarantine_is_not_supported_on_devices_of_OS_type_Linux': {
                                            runAfter: {}
                                            type: 'SetVariable'
                                            inputs: {
                                              name: 'ActionInfo'
                                              value: 'Note: Quarantine is not supported on devices of OS type Linux'
                                            }
                                            description: 'Set action information - Quarantine is not supported on devices of OS type Linux'
                                          }
                                        }
                                        runAfter: {}
                                        else: {
                                          actions: {
                                            Append_device_name: {
                                              runAfter: {
                                                'Set_device_actions_[_Quarantine_,_Ignore_]': [
                                                  'Succeeded'
                                                ]
                                              }
                                              type: 'AppendToArrayVariable'
                                              inputs: {
                                                name: 'DevicesActionNeeded'
                                                value: '@items(\'For_each_results\')?[\'id\']'
                                              }
                                              description: 'Append device name which needs SOC action'
                                            }
                                            'Set_action_information_-_The_device_is_assigned_to_predefined_policy': {
                                              runAfter: {}
                                              type: 'SetVariable'
                                              inputs: {
                                                name: 'ActionInfo'
                                                value: 'Note: The device is added to predefined policy @{items(\'For_each_results\')?[\'policy_name\']}'
                                              }
                                              description: 'Set action information - The device is added to predefined policy'
                                            }
                                            'Set_device_actions_[_Quarantine_,_Ignore_]': {
                                              runAfter: {
                                                'Set_action_information_-_The_device_is_assigned_to_predefined_policy': [
                                                  'Succeeded'
                                                ]
                                              }
                                              type: 'SetVariable'
                                              inputs: {
                                                name: 'DeviceActions'
                                                value: [
                                                  {
                                                    title: 'QUARANTINE'
                                                    value: 'QUARANTINE'
                                                  }
                                                  {
                                                    title: 'Ignore'
                                                    value: 'Ignore'
                                                  }
                                                ]
                                              }
                                              description: 'Set device actions [ Quarantine , Ignore ]'
                                            }
                                          }
                                        }
                                        expression: {
                                          and: [
                                            {
                                              equals: [
                                                '@toLower(items(\'For_each_results\')?[\'os\'])'
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
                                          true
                                        ]
                                      }
                                      {
                                        not: {
                                          equals: [
                                            '@items(\'For_each_results\')?[\'policy_id\']'
                                            '@variables(\'PredefinedPolicy\')'
                                          ]
                                        }
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
                                  not: {
                                    equals: [
                                      '@items(\'For_each_results\')?[\'policy_id\']'
                                      '@variables(\'PredefinedPolicy\')'
                                    ]
                                  }
                                }
                                {
                                  not: {
                                    equals: [
                                      '@items(\'For_each_results\')?[\'quarantined\']'
                                      true
                                    ]
                                  }
                                }
                                {
                                  not: {
                                    equals: [
                                      '@tolower(items(\'For_each_results\')?[\'os\'])'
                                      'linux'
                                    ]
                                  }
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
                              true
                            ]
                          }
                          {
                            equals: [
                              '@items(\'For_each_results\')?[\'policy_id\']'
                              '@variables(\'PredefinedPolicy\')'
                            ]
                          }
                          {
                            equals: [
                              ''
                              ''
                            ]
                          }
                        ]
                      }
                      type: 'If'
                      description: 'Verify the device is Quarantied'
                    }
                    Condition_to_check_the_device_actions: {
                      actions: {
                        Set_adaptive_card_columns_list_with_choices: {
                          runAfter: {}
                          type: 'SetVariable'
                          inputs: {
                            name: 'AdaptivecardColumnsList'
                            value: {
                              items: [
                                {
                                  text: '@{items(\'For_each_results\')?[\'id\']} @{items(\'For_each_results\')?[\'name\']} @{items(\'For_each_results\')?[\'organization_name\']}'
                                  type: 'TextBlock'
                                  weight: 'Bolder'
                                }
                                {
                                  text: 'Device system operation is @{items(\'For_each_results\')?[\'os\']} @{items(\'For_each_results\')?[\'os_version\']}'
                                  type: 'TextBlock'
                                }
                                {
                                  text: 'Owner is @{items(\'For_each_results\')?[\'first_name\']} @{items(\'For_each_results\')?[\'last_name\']} @{items(\'For_each_results\')?[\'email\']}'
                                  type: 'TextBlock'
                                }
                                {
                                  text: 'Device policy is @{items(\'For_each_results\')?[\'policy_name\']} @{items(\'For_each_results\')?[\'policy_id\']}'
                                  type: 'TextBlock'
                                }
                                {
                                  text: 'Sensor states are : @{body(\'Join_sensor_states_results\')}'
                                  type: 'TextBlock'
                                  wrap: true
                                }
                                {
                                  text: '@{variables(\'ActionInfo\')}'
                                  type: 'TextBlock'
                                  weight: 'Bolder'
                                  wrap: true
                                }
                                {
                                  choices: '@variables(\'DeviceActions\')'
                                  id: '@{items(\'For_each_results\')?[\'id\']}'
                                  placeholder: 'Please choose'
                                  style: 'compact'
                                  type: 'Input.ChoiceSet'
                                  value: 'Ignore'
                                }
                              ]
                              type: 'Column'
                              width: 'stretch'
                            }
                          }
                          description: 'Set adaptive card columns list with choice list [ Quarantine , Update_Policy , Ignore ]'
                        }
                      }
                      runAfter: {
                        Join_sensor_states_results: [
                          'Succeeded'
                        ]
                      }
                      else: {
                        actions: {
                          Set_adaptive_card_columns_list_without_choices: {
                            runAfter: {}
                            type: 'SetVariable'
                            inputs: {
                              name: 'AdaptivecardColumnsList'
                              value: {
                                items: [
                                  {
                                    text: '@{items(\'For_each_results\')?[\'id\']} @{items(\'For_each_results\')?[\'name\']} @{items(\'For_each_results\')?[\'organization_name\']}'
                                    type: 'TextBlock'
                                    weight: 'Bolder'
                                  }
                                  {
                                    text: 'Device system operation is @{items(\'For_each_results\')?[\'os\']} @{items(\'For_each_results\')?[\'os_version\']}'
                                    type: 'TextBlock'
                                  }
                                  {
                                    text: 'Owner is @{items(\'For_each_results\')?[\'first_name\']} @{items(\'For_each_results\')?[\'last_name\']} @{items(\'For_each_results\')?[\'email\']}'
                                    type: 'TextBlock'
                                  }
                                  {
                                    text: 'Device policy is @{items(\'For_each_results\')?[\'policy_name\']} @{items(\'For_each_results\')?[\'policy_id\']}'
                                    type: 'TextBlock'
                                  }
                                  {
                                    text: 'Sensor states are: @{body(\'Join_sensor_states_results\')}'
                                    type: 'TextBlock'
                                    wrap: true
                                  }
                                  {
                                    text: '@{variables(\'ActionInfo\')}'
                                    type: 'TextBlock'
                                    weight: 'Bolder'
                                    wrap: true
                                  }
                                ]
                                type: 'Column'
                                width: 'stretch'
                              }
                            }
                            description: 'Set adaptive card columns list without choice list'
                          }
                        }
                      }
                      expression: {
                        and: [
                          {
                            greater: [
                              '@length(variables(\'DeviceActions\'))'
                              0
                            ]
                          }
                        ]
                      }
                      type: 'If'
                    }
                    Join_sensor_states_results: {
                      runAfter: {
                        Condition__to_check_the_device_is_Quarantined_and_policy_configured: [
                          'Succeeded'
                        ]
                      }
                      type: 'Join'
                      inputs: {
                        from: '@items(\'For_each_results\')?[\'sensor_states\']'
                        joinWith: ','
                      }
                      description: 'Join sensor states with comma separated to show in the adaptive card'
                    }
                  }
                  runAfter: {}
                  type: 'Foreach'
                  description: 'Iterate over results and take proper action to Quarantine or Update_Policy on device'
                }
              }
              runAfter: {
                Append_Hosts: [
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
              description: 'Verify the filter criteria provided in the search devices in the organization returned records'
            }
            Search_devices_in_your_organization: {
              runAfter: {
                Set_adaptive_card_body: [
                  'Succeeded'
                ]
              }
              type: 'ApiConnection'
              inputs: {
                body: {
                  query: 'name : @{items(\'For_each_Hosts\')?[\'HostName\']}'
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
            Set_adaptive_card_body: {
              runAfter: {}
              type: 'SetVariable'
              inputs: {
                name: 'AdaptivecardBody'
                value: [
                  {
                    size: 'large'
                    text: 'Suspicious Device - Azure Sentinel'
                    type: 'TextBlock'
                    weight: 'bolder'
                    wrap: true
                  }
                  {
                    text: 'Possible comprised device detected by the provider:  @{outputs(\'Compose_product_name\')}'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    text: ' @{triggerBody()?[\'object\']?[\'properties\']?[\'severity\']} Incident - Carbon Black Device Actions '
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: ' Incident No : @{triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\']}  '
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: 'Incident description'
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    text: '@{triggerBody()?[\'object\']?[\'properties\']?[\'description\']}'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    text: '[Click here to view the Incident](@{triggerBody()?[\'object\']?[\'properties\']?[\'incidentUrl\']})'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    size: 'Small'
                    style: 'Person'
                    type: 'Image'
                    url: 'https://avatars.githubusercontent.com/u/2071378?s=280&v=4'
                  }
                  {
                    text: 'Carbon Black'
                    type: 'TextBlock'
                    weight: 'Bolder'
                  }
                  {
                    text: 'Take action on the devices in this incident: '
                    type: 'TextBlock'
                    weight: 'Bolder'
                  }
                ]
              }
              description: 'Set adaptive card body '
            }
          }
          runAfter: {
            DeviceIds: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
          description: 'For each host found from the provider'
          runtimeConfiguration: {
            concurrency: {
              repetitions: 1
            }
          }
        }
        For_each_adaptive_card_columns: {
          foreach: '@variables(\'AdaptivecardColumns\')'
          actions: {
            Append_device_columns_to_adaptive_card_body: {
              runAfter: {}
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'AdaptivecardBody'
                value: '@item()'
              }
              description: 'Append each device columns list to adaptive card body'
            }
          }
          runAfter: {
            For_each_Hosts: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        For_each_hosts_information: {
          foreach: '@variables(\'deviceids\')'
          actions: {
            Condition_to_check_the_device_that_needs_SOC_action: {
              actions: {
                Switch: {
                  runAfter: {}
                  cases: {
                    Case_Ignore: {
                      case: 'Ignore'
                      actions: {
                        'Append_action_summary_-_Ignore': {
                          runAfter: {}
                          type: 'AppendToArrayVariable'
                          inputs: {
                            name: 'ActionSummary'
                            value: {
                              action: '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\'][outputs(\'SOC_Action\')]'
                              device: '@outputs(\'Device_id\')'
                              statuscode: '204'
                            }
                          }
                          description: 'Append action summary - Ignore'
                        }
                      }
                    }
                    Case_QUARANTINE: {
                      case: 'QUARANTINE'
                      actions: {
                        Condition_to_check_the_status_codes_on_QUARANTINE: {
                          actions: {
                            'Append_action_summary_-_Quarantine': {
                              runAfter: {}
                              type: 'AppendToArrayVariable'
                              inputs: {
                                name: 'ActionSummary'
                                value: {
                                  action: '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\'][outputs(\'SOC_Action\')]'
                                  device: '@outputs(\'Device_id\')'
                                  statuscode: '@outputs(\'device_actions_QUARANTINE\')[\'statusCode\']'
                                }
                              }
                              description: 'Append action summary - Quarantine'
                            }
                          }
                          runAfter: {
                            device_actions_QUARANTINE: [
                              'Succeeded'
                            ]
                          }
                          else: {
                            actions: {
                              'Append_action_summary_-_Action_not_successful': {
                                runAfter: {}
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'ActionSummary'
                                  value: {
                                    action: 'Not successful'
                                    device: '@outputs(\'Device_id\')'
                                    statuscode: '@outputs(\'device_actions_QUARANTINE\')[\'statusCode\']'
                                  }
                                }
                              }
                            }
                          }
                          expression: {
                            or: [
                              {
                                equals: [
                                  '@outputs(\'device_actions_QUARANTINE\')?[\'statusCode\']'
                                  200
                                ]
                              }
                              {
                                equals: [
                                  '@outputs(\'device_actions_QUARANTINE\')?[\'statusCode\']'
                                  204
                                ]
                              }
                            ]
                          }
                          type: 'If'
                        }
                        device_actions_QUARANTINE: {
                          runAfter: {}
                          type: 'ApiConnection'
                          inputs: {
                            body: {
                              action_type: 'QUARANTINE'
                              device_id: [
                                '@{outputs(\'Device_id\')}'
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
                    }
                    Case_UPDATE_POLICY: {
                      case: 'UPDATE_POLICY'
                      actions: {
                        'Condition__to_check_the_status_codes_-_UPDATE_POLICY': {
                          actions: {
                            'Append_action_summary_-_Update_Policy': {
                              runAfter: {}
                              type: 'AppendToArrayVariable'
                              inputs: {
                                name: 'ActionSummary'
                                value: {
                                  action: '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\'][outputs(\'SOC_Action\')]'
                                  device: '@outputs(\'Device_id\')'
                                  statuscode: '@outputs(\'device_actions_UPDATE_POLICY\')[\'statusCode\']'
                                }
                              }
                            }
                          }
                          runAfter: {
                            device_actions_UPDATE_POLICY: [
                              'Succeeded'
                            ]
                          }
                          else: {
                            actions: {
                              'Append_action_summary_-_Update_Policy_-_Action_not_successful': {
                                runAfter: {}
                                type: 'AppendToArrayVariable'
                                inputs: {
                                  name: 'ActionSummary'
                                  value: {
                                    action: 'Not successful'
                                    device: '@outputs(\'Device_id\')'
                                    statuscode: '@outputs(\'device_actions_UPDATE_POLICY\')[\'statusCode\']'
                                  }
                                }
                              }
                            }
                          }
                          expression: {
                            or: [
                              {
                                equals: [
                                  '@outputs(\'device_actions_UPDATE_POLICY\')?[\'statusCode\']'
                                  204
                                ]
                              }
                              {
                                equals: [
                                  '@outputs(\'device_actions_UPDATE_POLICY\')?[\'statusCode\']'
                                  200
                                ]
                              }
                            ]
                          }
                          type: 'If'
                        }
                        device_actions_UPDATE_POLICY: {
                          runAfter: {}
                          type: 'ApiConnection'
                          inputs: {
                            body: {
                              action_type: 'UPDATE_POLICY'
                              device_id: [
                                '@{outputs(\'Device_id\')}'
                              ]
                              options: {
                                policy_id: '@{variables(\'PredefinedPolicy\')}'
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
                    }
                  }
                  default: {
                    actions: {}
                  }
                  expression: '@body(\'Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response\')?[\'data\'][outputs(\'SOC_Action\')]'
                  type: 'Switch'
                }
              }
              runAfter: {
                SOC_Action: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  'Append_-_No_action_required': {
                    runAfter: {}
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'ActionSummary'
                      value: {
                        action: 'No action is required'
                        device: '@outputs(\'Device_id\')'
                        statuscode: '204'
                      }
                    }
                  }
                }
              }
              expression: {
                and: [
                  {
                    greater: [
                      '@length(body(\'Filter_the_action_needed_device\'))'
                      0
                    ]
                  }
                  {
                    not: {
                      equals: [
                        '@toLower(body(\'Filter_each_device_information\')?[0]?[\'os\'])'
                        'linux'
                      ]
                    }
                  }
                ]
              }
              type: 'If'
              description: 'Condition to check the device that needs SOC action'
            }
            Device_id: {
              runAfter: {}
              type: 'Compose'
              inputs: '@item()'
              description: 'Compose device name'
            }
            Filter_each_device_information: {
              runAfter: {
                Device_id: [
                  'Succeeded'
                ]
              }
              type: 'Query'
              inputs: {
                from: '@variables(\'CarbonBlackDeviceInfo\')'
                where: '@equals(item()?[\'id\'], outputs(\'Device_id\'))'
              }
              description: 'Filter device information returned from carbon black cloud'
            }
            Filter_the_action_needed_device: {
              runAfter: {
                Filter_each_device_information: [
                  'Succeeded'
                ]
              }
              type: 'Query'
              inputs: {
                from: '@variables(\'DevicesActionNeeded\')'
                where: '@equals(item(), outputs(\'Device_id\'))'
              }
              description: 'Filter the action needed device'
            }
            SOC_Action: {
              runAfter: {
                Filter_the_action_needed_device: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: '@string(outputs(\'Device_id\'))'
            }
          }
          runAfter: {
            Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response: [
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
        For_each_incident_configuration: {
          foreach: '@outputs(\'Compose_incident_configuration\')'
          actions: {
            Append_incident_configuration_to_adaptive_card_body: {
              runAfter: {}
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'AdaptivecardBody'
                value: '@item()'
              }
              description: 'Append each incident configuration item to adaptive card body'
            }
          }
          runAfter: {
            Compose_incident_configuration: [
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
        Incident_hosts: {
          runAfter: {
            Adaptive_card_body: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'Hosts'
                type: 'array'
                value: []
              }
            ]
          }
          description: 'Variable to store the hosts information'
        }
        Organization_Id: {
          runAfter: {
            Predefined_PolicyId: [
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
          description: 'Configured Organization Id'
        }
        Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response: {
          runAfter: {
            Compose_adaptive_card_body: [
              'Succeeded'
            ]
          }
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              body: {
                messageBody: '{\n    "type": "AdaptiveCard",\n    "body": @{outputs(\'Compose_adaptive_card_body\')},\n     "width":"auto",\n   "actions": [\n                    {\n                        "type": "Action.Submit",\n                        "title": "Submit"\n                    },\n                  {\n                        "type": "Action.Submit",\n                        "title": "Ignore"\n                    }\n   ],\n    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",\n    "version": "1.2"\n}'
                recipient: {
                  channelId: Teams_ChannelId
                }
                shouldUpdateCard: true
              }
              notificationUrl: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
              }
            }
            path: '/flowbot/actions/flowcontinuation/recipienttypes/channel/$subscriptions'
            queries: {
              groupId: Teams_GroupId
            }
          }
        }
        Post_your_own_adaptive_card_as_the_Flow_bot_to_a_channel: {
          runAfter: {
            Condition_to_check_the_summary_action_Ignore_or_Submit: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              messageBody: '{\n    "type": "AdaptiveCard",\n    "body": [\n  {\n    "size": "large",\n    "text": "Suspicious Device - Azure Sentinel",\n    "type": "TextBlock",\n    "weight": "bolder",\n    "wrap": true\n  },\n  {\n    "text": "Possible comprised device detected by the provider :  @{outputs(\'Compose_product_name\')}",\n    "type": "TextBlock",\n    "wrap": true\n  },\n  {\n    "text": " @{triggerBody()?[\'object\']?[\'properties\']?[\'severity\']} Incident - Carbon Black Device Actions ",\n    "type": "TextBlock",\n    "weight": "Bolder",\n    "wrap": true\n  },\n  {\n    "text": " Incident No: @{triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\']}  ",\n    "type": "TextBlock",\n    "weight": "Bolder",\n    "wrap": true\n  },\n  {\n    "text": "Incident description",\n    "type": "TextBlock",\n    "weight": "Bolder",\n    "wrap": true\n  },\n  {\n    "text": "@{triggerBody()?[\'object\']?[\'properties\']?[\'description\']}",\n    "type": "TextBlock",\n    "wrap": true\n  },\n  {\n    "text": "[Click here to view the Incident](@{triggerBody()?[\'object\']?[\'properties\']?[\'incidentUrl\']})",\n    "type": "TextBlock",\n    "wrap": true\n  },\n        {\n            "type": "TextBlock",\n           \n            "weight": "Bolder",\n            "text": "Below is the summary of actions taken on Devices by SOC",\n            "wrap": true\n        },\n    {\n  "columns": [\n    {\n      "items": @{body(\'Select_action_summary\')},\n      "type": "Column",\n      "wrap": true\n    }\n  ],\n  "separator": "true",\n  "type": "ColumnSet",\n  "width": "stretch"\n}\n ],\n"width":"auto",\n "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",\n "version": "1.2"\n}'
              recipient: {
                channelId: Teams_ChannelId
              }
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/flowbot/actions/adaptivecard/recipienttypes/channel'
            queries: {
              groupId: Teams_GroupId
            }
          }
        }
        Predefined_PolicyId: {
          runAfter: {
            'Entities_-_Get_Hosts': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'PredefinedPolicy'
                type: 'integer'
                value: PolicyId
              }
            ]
          }
          description: 'Variable to store the predefined PolicyId'
        }
        Select_action_summary: {
          runAfter: {
            Create_HTML_table: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@variables(\'ActionSummary\')'
            select: {
              text: 'DeviceId : @{item()?[\'device\']}     Action: @{item()?[\'action\']}  StatusCode: @{item()?[\'statuscode\']}'
              type: 'TextBlock'
              wrap: 'true'
            }
          }
        }
        Select_alert_product_names: {
          runAfter: {
            Devices_action_needed: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'additionalData\']?[\'alertProductNames\']'
            select: {
              text: '@item()'
            }
          }
          description: 'data operator to select the alert product name'
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
          teams: {
            connectionId: TeamsConnection.id
            connectionName: TeamsConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/teams'
          }
        }
      }
    }
  }
}
