#!/bin/bash

####################################################################################################
#
# Copyright (c) 2023, Jamf Software, LLC.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the JAMF Software, LLC nor the
#                 names of its contributors may be used to endorse or promote products
#                 derived from this software without specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
####################################################################################################
# Jamf Connect Logs Collection
# v1.0

#####################################################
############# Script Configuration Area #############
#####################################################

# Set custom path for Jamf Connect Logs, default is /Library/Application Support/JamfConnect/Logs/, use $4 in a Jamf Pro policy or edit value in script on line 38.
customPath="$4"

# Location of the AWS CLI binary.
awsBinary="/usr/local/bin/aws"

# The name of the target S3 bucket resource
s3Bucket=""

# The region of the S3 bucket to use. Example: us-east-1
s3BucketRegion=""

# AWS Profile Name
awsProfile=""

# AWS Folder
awsFolder=""


#####################################################
############ DO NOT EDIT BELOW THIS LINE ############
#####################################################


# Getting logged in user
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
compHostName=$( scutil --get LocalHostName )

# Find files that match the pattern in the default folder
log_files=$(find "/Library/Application Support/JamfConnect/Logs" -name 'JamfConnectLogs*.*.zip')
customPath_files=$(find "$customPath" -name 'JamfConnectLogs*.*.zip')

# Expected AWS CLI Binary TeamID
expectedAwscliTeamID="94KV3E626L"

################# Script Functions ##################

startLogs () {
	
	if [ "$customPath" == "" ]; then
		echo "Staring Jamf Connect Logs collection"
		/usr/local/bin/jamfconnect logs --filename JamfConnectLogs-"$compHostName"-"$loggedInUser"
	else
		echo "Staring Jamf Connect Logs collection, exported to $customPath"
		/usr/local/bin/jamfconnect logs --output-directory "$customPath" --filename JamfConnectLogs-"$compHostName"-"$loggedInUser"	
	fi
}

# Checks for the Jamf Connect Logs archive to confirm if the script should continue
CheckForFiles () {
	
	if [ -n "$log_files" ] || [ -n "$customPath_files" ]; then
		echo "Jamf Connect Log Files found"
	else
		echo "Jamf Connect Logs Files were not found, exiting script"
		exit 1
	fi
}

# Upload the Jamf Connect Logs archive to Amazon S3 using the AWS CLI
CollectArchive () {
	if [[ -n "$s3Bucket" ]] && [[ -n "$s3BucketRegion" ]]; then
		
		# Check for the AWS binary. If not present, install.
		if [[ ! -f "$awsBinary" ]]; then    
			/usr/bin/curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
			/usr/sbin/installer -pkg /tmp/AWSCLIV2.pkg -target /
		
			# Verify the download
			teamID=$(/usr/sbin/spctl -a -vv -t install "/tmp/AWSCLIV2.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

			# Install and clean up the package if Team ID validates
			if [ "$expectedAwscliTeamID" = "$teamID" ] || [ "$expectedAwscliTeamID" = "" ]; then
				echo "AWSCLI Team ID verification succeeded"
				/usr/sbin/installer -pkg /tmp/AWSCLIV2.pkg -target /
				/bin/rm /tmp/AWSCLIV2.pkg
			else
				echo "AWSCLI Team ID verification failed."
				/bin/rm /tmp/AWSCLIV2.pkg
				exit 1
			fi
		fi
		
		export awsInstallStatus=$?
		
		if [[ "$awsInstallStatus" -eq 0 ]]; then
			echo "Installing AWS shared credentials."
			/usr/local/bin/jamf policy -event aws_creds
			export awsCredsStatus=$?
		else
			echo "AWS CLI is not installed. Please try again."
			exit 1
		fi
		
		if [[ "$awsCredsStatus" -eq 0 ]]; then
			export AWS_PROFILE="$awsProfile"
			export AWS_CONFIG_FILE="$awsFolder"/config
			export AWS_SHARED_CREDENTIALS_FILE="$awsFolder"/credentials
			
			# Use the AWS CLI to copy the archive to the desginated bucket
			if [ "$customPath" == "" ]; then
				echo "The AWS binary is present, initiating the upload.."
				"$awsBinary" s3 cp "/Library/Application Support/JamfConnect/Logs/" s3://"$s3Bucket" --recursive --exclude "*" --include "JamfConnectLogs*"
			else
				echo "The AWS binary is present, initiating the upload.."
				"$awsBinary" s3 cp "$customPath" s3://"$s3Bucket" --recursive --exclude "*" --include "JamfConnectLogs*"
			fi
			
			export uploadStatus=$?
			
			# Report back the status of the upload
			if [[ "$uploadStatus" -eq 0 ]]; then
				echo "The upload to S3 was successful and finished with exit code ${uploadStatus}."
			else
				echo "The upload to S3 failed with error code ${uploadStatus}."
			fi
		else
			echo "AWS shared credentials are not present. Please try again."
			exit 1
		fi
		
	else
		
		echo "S3 information was not configured."
		export uploadStatus="1"
		
	fi
}

# Check for the required network connectivity to use the AWS S3 service
NetworkCheckAndUpload () {
	if /usr/bin/nc -zdw1 s3.amazonaws.com 443; then
		networkUP="yes"
		echo "Can the device connect to the S3 bucket for upload? Result: ${networkUP}"
		echo "Network connectivity is available so the upload will proceed."
		
		# Call CollectArchive function
		CollectArchive
	else
		networkUP="no"
		echo "Can the device connect to the S3 bucket for upload? Result: ${networkUP}"
		echo "Network connectivity is not available, exiting."
		exit 1
	fi
}

# Clean up and end this workflow
CleanUp () {
	
	# Clean up the Jamf Connect Logs archive if upload was sucecessful
	echo "Removing Jamf Connect Logs archive."
	if [[ "$uploadStatus" -eq 0 ]] && [[ "$customPath" == "" ]]; then
		/bin/rm "/Library/Application Support/JamfConnect/Logs/"*
	elif [[ "$uploadStatus" -eq 0 ]]; then
		/bin/rm "$customPath"JamfConnectLogs*
	fi
	
	# Remove AWS CLI and .aws directory
	echo "Removing aws cli and .aws folder"
	/bin/rm /usr/local/bin/aws
	/bin/rm /usr/local/bin/aws_completer
	/bin/rm -rf /usr/local/aws-cli
	/bin/rm -rf /opt/.aws
}

startLogs
CheckForFiles
CollectArchive
NetworkCheckAndUpload 
cleanUp

