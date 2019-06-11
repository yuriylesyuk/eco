# eco Edge Clone Organization command


The eco.sh script (Edge Clone Organization) can import and export organizations, environments and virtual hosts of an organization and import them into another organization that it will create.


Usage: 
  1. Edit eco.sh and setup a couple of environement variables
       MSURL=

  2. Execute test command to Management server

  if you want to use curl -n (recommended), do not setup following variables:
       SYSADMINEMAIL=
       SYSADMINPASSWORD=

## To export org structure (org, envs, and vhosts): 
  
    eco.sh export org > org-def.json

It will generate json file. As required. 

Of cause, if you want to import it into the same planet, you better edit it so that there is no org name or port allocation conflicts.


##  To import org structure, i.e., org, envs, and vhosts

    eco.sh import org3-def.json 2>&1 |tee org3-def.log

It will create org, envs and its vhosts.


Example organization configurations are in the docs/examples folder.
