#!/bin/bash
#
#
# Aws Budgets cretion script
#
#

# Basic Utilities

# Write colored output recieve "colournumber" "message"
function colecho(){
        SETCOLOR_SUCCESS="echo -en \\033[1;32m";
        SETCOLOR_NORMAL="echo -en \\033[0;39m";
        SETCOLOR_FAILURE="echo -en \\033[1;31m";
        SETCOLOR_WARNING="echo -en \\033[1;33m";
        [ "$1" == "" ] && $SETCOLOR_NORMAL;
        [ "$1" == "0" ] && $SETCOLOR_SUCCESS;
        [ "$1" == "1" ] && $SETCOLOR_FAILURE;
        [ "$1" == "2" ] && $SETCOLOR_WARNING;
        [ "$2" == "" ] || echo "$2";
        $SETCOLOR_NORMAL;
}

function error(){
        [ "$1" == "" ] && usage || colecho "1" "$1";
        exit 1;
}

function usage(){
PNAME=`basename $0`
cat << EOF
Disclaimer: 
        This script will create a cloudformation stack that manages alert for a budget entity.
Usage:
        $PNAME [OPTION]
Options:
        -h|H
                Print this help and exit
        -a|A
                Amount of your budget is for the month (mandatory)
        -e|E
                Email address to send notifications to (mandatory)
EOF
        exit 0;
}

function createcf(){
cat <<EOF 
AWSTemplateFormatVersion: '2010-09-09'
Description: Creates an AWS budget and notifies you when you exceed thresholds.
Parameters:
  Name:
    Description: The name of the budget
    Type: String
    Default: Budget
  Amount:
    Description: What your budget is for the month
    Type: Number
  Currency:
    Description: The currency of your budget
    Type: String
    Default: USD
  FirstThreshold:
    Description: The first threshold at which you'll receive a notification
    Type: Number
    Default: 75
  SecondThreshold:
    Description: The second threshold at which you'll receive a notification
    Type: Number
    Default: 99
  Email:
    Description: The email address to send notifications to
    Type: String
# Order the parameters in a way that makes more sense (not alphabetized)
Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
      - Parameters:
          - Name
          - Amount
          - Currency
          - FirstThreshold
          - SecondThreshold
          - Email
Resources:
  Budget:
    Type: AWS::Budgets::Budget
    Properties:
      Budget:
        BudgetName: !Ref Name
        BudgetLimit:
          Amount: !Ref Amount
          Unit: !Ref Currency
        TimeUnit: MONTHLY
        BudgetType: COST
      # "A budget can have up to five notifications. Each notification must have at least one subscriber.
      # A notification can have one SNS subscriber and up to ten email subscribers, for a total of 11 subscribers."
      NotificationsWithSubscribers:
        - Notification:
            ComparisonOperator: GREATER_THAN
            NotificationType: ACTUAL
            Threshold: !Ref FirstThreshold
            ThresholdType: PERCENTAGE
          Subscribers:
            - SubscriptionType: EMAIL
              Address: !Ref Email
        - Notification:
            ComparisonOperator: GREATER_THAN
            NotificationType: ACTUAL
            Threshold: !Ref SecondThreshold
            ThresholdType: PERCENTAGE
          Subscribers:
            - SubscriptionType: EMAIL
              Address: !Ref Email
        - Notification:
            ComparisonOperator: GREATER_THAN
            NotificationType: FORECASTED
            Threshold: 100
            ThresholdType: PERCENTAGE
          Subscribers:
            - SubscriptionType: EMAIL
              Address: !Ref Email
EOF
}

TMPNAME=./.`basename $0`.$$;

# Options Parser
while getopts "hHa:A:e:E:" opt "$@"
do
        case $opt in
                a|A) AMOUNT=$OPTARG;;
                e|E) EMAIL=$OPTARG;;
                h|H) usage;;
                *) error "Unknown option!";
        esac
done
[ -z "${AMOUNT}" ] && error "Budget for the month is mandatory";
[ -z "${EMAIL}" ] && error "Email address is mandatory";

[ $AMOUNT -eq $AMOUNT 2>/dev/null ] || error "Budget is not a number";

AWS_BIN=$(which aws 2> /dev/null)
[ -z "${AWS_BIN}"  ] && error "Aws Cli is missing, install awscli and retry";

NAME=$( echo "${EMAIL}" | tr -dc '[:alnum:]'; )
APPDN="Budget${NAME}${AMOUNT}";
CURRENCY="USD";
FSTTSHD="80";
SNDTSHD="95";

createcf > ${TMPNAME};

aws cloudformation create-stack  --stack-name ${APPDN} \
    --template-body file://${TMPNAME} \
    --parameters \
      ParameterKey=Name,ParameterValue=${NAME} \
      ParameterKey=Amount,ParameterValue=${AMOUNT} \
      ParameterKey=Currency,ParameterValue=${CURRENCY} \
      ParameterKey=FirstThreshold,ParameterValue=${FSTTSHD} \
      ParameterKey=SecondThreshold,ParameterValue=${SNDTSHD} \
      ParameterKey=Email,ParameterValue=${EMAIL} 

[ -f "${TMPNAME}" ] && rm -f ${TMPNAME};
