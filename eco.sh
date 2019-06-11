#!/bin/bash

#
# eco Edge Copy Organization command
#
# Usage: 
#   1. setup env variables
#        MSURL=
#
#
#
#
#   if you want to use curl -n, do not setup following variables:
#        SYSADMINEMAIL=
#        SYSADMINPASSWORD=
#
# To export org structure: 
#   eco.sh export org 
#
# To import org structrue:
#   eco.sh import orgfiledef.json
#

# https://docs.apigee.com/private-cloud/v4.18.05/provisioning-organizations

export MSURL=http://10.154.0.9:8080
export PROXYURL=http://10.154.0.9:9001

export SRCORG=org

export ORG=org2
export ENV=prod


export SYSADMINEMAIL=admin@exco.com
export SYSADMINPASSWORD=Apigee123!

export ORGADMINFNAME=Fname
export ORGADMINLNAME=Lname
export ORGADMINPASSWORD=Apigee123!
export ORGADMINEMAIL=orgadmin@exco.com

# setup authentication
if [ ! -z "$SYSADMINEMAIL" ] && [ -e "$ORG_ADMIN_PASSWORD" ]; then
    curlauth="-u \"$SYSADMINEMAIL\"\"$ORG_ADMIN_PASSWORD\""
else
    curlauth="-n"
fi

# test curl ms
# curl -n $MSURL/v1/o

set -e

action=$1
param=$2

#----------------------------------------------------------------------
##
## analyze source org
##
#----------------------------------------------------------------------
if [ "$action" = "export" ]; then

SRCORG=$param

orgenvs=$( curl -s $curlauth -H "Content-Type: application/json" $MSURL/v1/organizations/$SRCORG/environments )
envs=${orgenvs//[\",\[\]]/}


echo -e "{\n    \"org\" : {"
echo "        \"name\" : \"$SRCORG\","
echo "        \"envs\" : ["
for e in $envs; do
    envvhosts=$( curl -s $curlauth -H "Content-Type: application/json" $MSURL/v1/organizations/$SRCORG/environments/$e/virtualhosts )
    vhosts=${envvhosts//[\",\[\]]/}
    
echo "             $envsep"
echo "             {"
echo "                 \"name\" : \"$e\","

echo "                 \"hosts\" : ["
    
        for vhost in $vhosts; do
echo "                     $hostsep"
echo "                     {"
echo "                         \"name\" : \"$vhost\","
        envvhosts=$( curl -s $curlauth -H "Content-Type: application/json" $MSURL/v1/organizations/$SRCORG/environments/$e/virtualhosts/$vhost )

        hostaliases=$( echo -e  "$envvhosts" | awk '/\"hostAliases\" : \[/{match($0, /\: \[ .+\]/);print substr($0,RSTART+4,RLENGTH-6) }' )
        port=$( echo -e  "$envvhosts" | awk '/\"port\" : "[0-9]+"/{ gsub(/[",]/, "", $3 );print $3 }' )

echo "                         \"hostaliases\" : [ " $hostaliases " ],"
echo "                         \"port\" :" $port
echo "                     }"
        hostsep=","
    done


echo "                    ]"
echo "                }"
echo "           ]"

        envsep=","
done 

echo "    }"
echo "}"

#----------------------------------------------------------------------



#----------------------------------------------------------------------
##
##  create target org
##
# provison org admin user
#----------------------------------------------------------------------
elif [ "$action" = "import" ]; then

orgconfigfile=$param

# parse org program into ast by using org grammar
orgast=($( awk '
function push(token){ stack[++stackptr]=token }
function pop(){return stack[stackptr--] }
function top(backtrack){ return stack[stackptr + backtrack] }
BEGIN{ org=""; env=""; vhost=""; #stack=[]; stackptr=0; push("START") 
}
/"org" :/{ push( "ORG" ) }
/"envs" :/{ push( "ENV" ) }
/"hosts" :/{ push( "VHOST" ) }
/"name" :/{ gsub(/[",]/, "", $3 );  name = $3 ; if( top()=="ORG" ){print top() ":" name};
    if(top(-1)=="ENV" && top(0)=="BLOCK"){ print top(-1) ":" name } }
/"hostaliases" :/{ match($0, /\: \[ .+\]/); hostaliases=substr($0,RSTART+4,RLENGTH-6); gsub(" ","",hostaliases) }
/"port" :/{ port=$3 }
/^[ ]*\{/{ if(top()!="ORG"){push("BLOCK") }; }
/^[ ]*\}/{ if(top(-1)=="VHOST" && top(0)=="BLOCK"){ print top(-1) ":" name "," port ";" hostaliases }; pop() }
/^[ ]*\]/{ pop() }
' $orgconfigfile ))


# define org admin user
curl $curlauth -H "Content-Type: application/json" \
    -X POST $MSURL/v1/users -d "{ \
        \"firstName\" : \"$ORGADMINFNAME\", \
        \"lastName\" : \"$ORGADMINLNAME\", \
        \"password\" : \"$ORGADMINPASSWORD\", \
        \"emailId\" : \"$ORGADMINEMAIL\"  \
    }"

# 

# interpret ast
for i in "${orgast[@]}"
do
    token=${i%%:*}
    value=${i##*:}

    if [ "$token" = "ORG" ]; then
        ORG=$value

        ## create org
        curl $curlauth -H "Content-Type: application/json" \
            -X POST $MSURL/v1/organizations -d "{
                \"name\" : \"$ORG\", \
                \"type\": \"paid\" \
            }"



        # associates the org with a pod
        curl $curlauth -H "Content-Type:application/x-www-form-urlencoded" \
            -X POST $MSURL/v1/organizations/$ORG/pods \
            -d "region=dc-1&pod=gateway"

        # adds org admin for the org:
        curl $curlauth -H "Content-Type:application/x-www-form-urlencoded" \
            -X POST $MSURL/v1/organizations/$ORG/userroles/orgadmin/users?id=$ORGADMINEMAIL


    elif [ "$token" = "ENV" ]; then
        ENV=$value

        ## create an environment
        curl $curlauth -H "Content-Type: application/json" \
            -X POST $MSURL/v1/organizations/$ORG/environments -d "{
                \"name\" : \"$ENV\" \
            }"


        # collect UUIDs of all Message Processors and extract mp uuids
        gatewayservers=$( curl $curlauth $MSURL/v1/servers?pod=gateway )
        mps=$( echo -e  "$gatewayservers" | awk '/\"type\" : \[ \"message-processor\" \]/{ getline; gsub(/[",]/, "", $3 );print $3 }' )

        centralservers=$( curl $curlauth $MSURL/v1/servers?pod=central )
        qss=$( echo -e  "$centralservers" | awk '/\"type\" : \[ \"qpid-server\" \]/{ getline; printf "%s%s", sep, $3; sep=", " }' )

        analyticsservers=$( curl $curlauth $MSURL/v1/servers?pod=analytics )
        pss=$( echo -e  "$analyticsservers" | awk '/\"type\" : \[.*\"postgres-server\".*\]/{ getline; printf "%s%s", sep, $3; sep=", " }' )


        # associates the environment with all Message Processors
        for uuid in $mps; do
            curl $curlauth -H "Content-Type:application/x-www-form-urlencoded" \
                -X POST $MSURL/v1/organizations/$ORG/environments/$ENV/servers \
                -d "action=add&uuid=$uuid"
        done

        # enable analytics for an environment
        curl $curlauth -H "Content-Type: application/json" \
            -X POST $MSURL/v1/organizations/$ORG/environments/$ENV/analytics/admin -d "{  \
                \"properties\" : { \
                    \"samplingAlgo\" : \"reservoir_sampler\", \
                    \"samplingTables\" : \"10=ten;1=one;\", \
                    \"aggregationinterval\" : \"300000\", \
                    \"samplingInterval\" : \"300000\", \
                    \"useSampling\" : \"100\", \
                    \"samplingThreshold\" : \"100000\" \
                }, \
                \"servers\" : { \
                    \"postgres-server\" : [ $pss ],  \
                    \"qpid-server\" : [ $qss ]  \
                } \
            }"


    elif [ "$token" = "VHOST" ]; then
        # default3,9007;"org2-prod.exco.com","10.157.0.14"
        vhostporthostaliases=${value%%;*}
        vhostport=${value%%;*}
        hostaliases=${value##*;}
        vhost=${vhostport%%,*}
        port=${vhostport##*,}



        ## create virtual host
        curl $curlauth -H "Content-Type: application/json" \
            -X POST $MSURL/v1/organizations/$ORG/environments/$ENV/virtualhosts -d "{ \
                \"name\": \"$vhost\", \
                \"hostAliases\": [ $hostaliases ], \
                \"port\": \"$port\" \
            }"
    else
        ccho "ERROR: Unknown token: $token"
    fi
done

#----------------------------------------------------------------------

else
    echo "Unknown action: $action"

fi
#----------------------------------------------------------------------










