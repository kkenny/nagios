#
# Author:: Joshua Sierles <joshua@37signals.com>
# Author:: Joshua Timberman <joshua@opscode.com>
# Author:: Nathan Haneysmith <nathan@opscode.com>
# Author:: Seth Chisamore <schisamo@opscode.com>
# Cookbook Name:: nagios
# Recipe:: client
#
# Copyright 2009, 37signals
# Copyright 2009-2011, Opscode, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

node.set_unless['nagios']['monitored'] = node['nagios']['monitor']

mon_host = []
if node.run_list.roles.include?(node['nagios']['server_role'])
  mon_host << node['ipaddress']
elsif node['nagios']['multi_environment_monitoring']
  search(:node, "role:#{node['nagios']['server_role']}") do |n|
   mon_host << n['ipaddress']
  end
else
  search(:node, "role:#{node['nagios']['server_role']} AND chef_environment:#{node.chef_environment}") do |n|
    mon_host << n['ipaddress']
  end
end

## HACK ##
mon_host << '172.20.99.249'

include_recipe "nagios::client_#{node['nagios']['client']['install_method']}"

remote_directory node['nagios']['plugin_dir'] do
  source "plugins"
  owner "root"
  group "root"
  mode 0755
  files_mode 0755
end

directory "#{node['nagios']['nrpe']['conf_dir']}/nrpe.d" do
  owner "root"
  group "root"
  mode 0755
end

template "#{node['nagios']['nrpe']['conf_dir']}/nrpe.cfg" do
  source "nrpe.cfg.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :mon_host => mon_host,
    :nrpe_directory => "#{node['nagios']['nrpe']['conf_dir']}/nrpe.d"
  )
  notifies :restart, "service[nagios-nrpe-server]"
end

template "#{node['nagios']['plugin_dir']}/check_procs.sh" do
  source "check_procs.sh.erb"
  owner "root"
  group "root"
  mode "0755"
end

service "nagios-nrpe-server" do
  action [:start, :enable]
  supports :restart => true, :reload => true
end

# Use NRPE LWRP to define a few checks
nagios_nrpecheck "check_load" do
  command "#{node['nagios']['plugin_dir']}/check_load"
  warning_condition node['nagios']['checks']['load']['warning']
  critical_condition node['nagios']['checks']['load']['critical']
  action :add
end

nagios_nrpecheck "check_all_disks" do
  command "#{node['nagios']['plugin_dir']}/check_disk"
  warning_condition "8%"
  critical_condition "5%"
  parameters "-A -x /dev/shm -X nfs -i /boot"
  action :add
end

nagios_nrpecheck "check_users" do
  command "#{node['nagios']['plugin_dir']}/check_users"
  warning_condition "20"
  critical_condition "30"
  action :add
end

if node.run_list.roles.include?("chef_server")
  nagios_nrpecheck "check_chef_server" do
    command "#{node['nagios']['plugin_dir']}/check_procs"
    warning_condition "1:1"
    critical_condition "1:1"
    parameters "-C chef-server"
    action :add
  end

  nagios_nrpecheck "check_chef_server_webui" do
    command "#{node['nagios']['plugin_dir']}/check_chef_server_webui.sh"
    action :add
  end

  nagios_nrpecheck "check_chef_expander" do
    command "#{node['nagios']['plugin_dir']}/check_chef_expander.sh"
    action :add
  end
end

if node.run_list.roles.include?("apache_server")
  nagios_nrpecheck "check_proc_apache" do
    command "#{node['nagios']['plugin_dir']}/check_procs"
    parameters "-C apache2"
    warning_condition "2:"
    critical_condition "1:"
    action :add
  end
end

if node.run_list.roles.include?("load_balancer")
  nagios_nrpecheck "check_proc_apache" do
    command "#{node['nagios']['plugin_dir']}/check_procs"
    parameters "-C apache2"
    warning_condition "2:"
    critical_condition "1:"
    action :add
  end
end

if node.run_list.roles.include?("mysql_master")
  nagios_nrpecheck "check_mysql" do
    command "#{node['nagios']['plugin_dir']}/check_mysql -H localhost -uroot -p#{node['mysql']['server_root_password']}"
  end
end

if node.run_list.roles.include?("mysql_slave")
  nagios_nrpecheck "check_mysql" do
    command "#{node['nagios']['plugin_dir']}/check_mysql -H localhost -uroot -p#{node['mysql']['server_root_password']}"
  end
end
