# JamfSiteExtCopy
 Copies Jamf Site to Extension Attribute

**Usage**

    `jamfSiteExtCopy.sh [-v] [-c] [-m] [-s <server name>] [-u <client id>] [-p <client secret>]`

Downloads computer and mobile devices information from a Jamf Pro server API and sets the 'Jamf Site' extension attribute to the value of the item's Jamf site if that is not already set.'

Uses API keys which can be set up through the Jamf Pro server (curently under Settings -> System -> API Roles and Clients). If the server name and/or credentials are not specified, the script will prompt for them.

The role assigned to the API client ID must have access to read and update Computers, read and update Mobile Devices, and update Users, or else the Jamf Pro server will return an authorization error for some operations. 

**Options**
    `-s <server name>`
    
        Specify the server name (URL) of the Jamf Pro server
        
    `-u <client id>`
    
        Specify the client ID for the Jamf Pro server API
        
    `-p <client secret>`
    
        Specify the client secret for the Jamf Pro server API
        
    `-c`
    
        Skip computers (only check mobile devices) mode
        
    `-m`
    
        Skip mobile devices (only check computers) mode
        
    `-v`
    
        Sets verbose (debug) mode