#!/bin/bash
#
#   cloudforms_essentialsrc
#
#   Author: Kevin Morey <kevin@redhat.com>
#
#   Description: This bash script initializes some useful aliases that assist CloudForms
#                administrators logged into the appliance
#
#   Installation: Place this file in root's home direcotry and then source this file.
#
#   -------------------------------------------------------------------------------
#    Copyright 2016 Kevin Morey <kevin@redhat.com>
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
# -------------------------------------------------------------------------------

# Directory aliases
alias lib='cd /var/www/miq/lib'
alias log='cd /var/www/miq/vmdb/log'

# Tail aliases
alias auto='tail -f /var/www/miq/vmdb/log/automation.log'
alias evm='tail -f /var/www/miq/vmdb/log/evm.log'
alias aws='tail -f /var/www/miq/vmdb/log/aws.log'
alias foglog='tail -f /var/www/miq/vmdb/log/fog.log'
alias rhevm='tail -f /var/www/miq/vmdb/log/rhevm.log'
alias prod='tail -f /var/www/miq/vmdb/log/production.log'
alias policy='tail -f /var/www/miq/vmdb/log/policy.log'
alias pglog='tail -f /opt/rh/postgresql92/root/var/lib/pgsql/data/pg_log/postgresql.log'

# Clean logging aliases
alias clean="echo Cleaned: `date` > /var/www/miq/vmdb/log/automation.log;echo Cleaned: `date` > /var/www/miq/vmdb/log/evm.log;echo Cleaned: `date` > /var/www/miq/vmdb/log/production.log;clear;echo Logs cleaned..."
alias clean_evm="echo Cleaned: `date` > /var/www/miq/vmdb/log/evm.log"
alias clean_aws="echo Cleaned: `date` > /var/www/miq/vmdb/log/aws.log"
alias clean_rhevm="echo Cleaned: `date` > /var/www/miq/vmdb/log/rhevm.log"
alias clean_fog="echo Cleaned: `date` > /var/www/miq/vmdb/log/fog.log"
alias clean_auto="echo Cleaned: `date` > /var/www/miq/vmdb/log/automation.log"
alias clean_prod="echo Cleaned: `date` > /var/www/miq/vmdb/log/production.log"
alias clean_policy="echo Cleaned: `date` > /var/www/miq/vmdb/log/policy.log"
alias clean_pgsql="echo Cleaned: `date` > /opt/rh/postgresql92/root/var/lib/pgsql/data/pg_log/postgresql.log"

# Rails Console
alias railsc="cd /var/www/miq/vmdb;echo '\$evm = MiqAeMethodService::MiqAeService.new(MiqAeEngine::MiqAeWorkspaceRuntime.new)'; script/rails c"

# kill provision job.
function kill_prov {
  vmdb
  script/rails r tools/kill_provision.rb $1
  cd - > /dev/null 2>&1
}

# Application Status
alias status='echo "CloudForms Status:";service evmserverd status;echo " ";echo "HTTP Status:";service httpd status'

# Ignore duplicate history commands
export HISTCONTROL=ignoredups
