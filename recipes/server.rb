#
# Author:: Joshua Sierles <joshua@37signals.com>
# Author:: Joshua Timberman <joshua@opscode.com>
# Author:: Nathan Haneysmith <nathan@opscode.com>
# Author:: Seth Chisamore <schisamo@opscode.com>
# Cookbook Name:: nagios
# Recipe:: server
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

include_recipe "apache2"
include_recipe "apache2::mod_ssl"
include_recipe "apache2::mod_rewrite"
include_recipe "nagios::client"

sysadmins = search(:admins, 'groups:admin')

nodes = search(:node, "fqdn:[* TO *] AND chef_environment:#{node.chef_environment} AND role:nagios_client")
Chef::Log.info("Monitoring these nodes:\n #{nodes}")

begin
  services = search(:nagios_services, '*:*')
rescue Net::HTTPServerException
  Chef::Log.info("Search for nagios_services data bag failed, so we'll just move on.")
end

if services.nil? || services.empty?
  Chef::Log.info("No services returned from data bag search.")
  services = Array.new
end

if nodes.empty?
  Chef::Log.info("No nodes returned from search, using this node so hosts.cfg has data")
  nodes = Array.new
  nodes << node
end

members = Array.new
sysadmins.each do |s|
  members << s['id']
end

role_list = Array.new
service_hosts = Hash.new
search(:role, "*:*") do |r|
  role_list << r.name
  search(:node, "role:#{r.name} AND chef_environment:#{node.chef_environment}") do |n|
    service_hosts[r.name] = n['fqdn']
  end
end

#role_list << "carbon_metrics"
#role_list << "graphite_server"
#role_list << "mysql_master_server_for_graphite"
#role_list << "mysql_slave_server_for_graphite"
#role_list << "graphite_relay"

if node['public_domain']
  public_domain = node['public_domain']
else
  public_domain = node['domain']
end

include_recipe "nagios::server_#{node['nagios']['server']['install_method']}"

nagios_conf "nagios" do
  config_subdir false
end

#directory "/var/lib/nagios3/spool/graphios" do
#  owner node['nagios']['user']
#  group node['nagios']['group']
#  mode "0755"
#end

directory "#{node['nagios']['conf_dir']}/dist" do
  owner node['nagios']['user']
  group node['nagios']['group']
  mode "0755"
end

directory node['nagios']['state_dir'] do
  owner node['nagios']['user']
  group node['nagios']['group']
  mode "0751"
end

directory "#{node['nagios']['state_dir']}/rw" do
  owner node['nagios']['user']
  group node['apache']['user']
  mode "2710"
end

execute "archive-default-nagios-object-definitions" do
  command "mv #{node['nagios']['config_dir']}/*_nagios*.cfg #{node['nagios']['conf_dir']}/dist"
  not_if { Dir.glob("#{node['nagios']['config_dir']}/*_nagios*.cfg").empty? }
end

file "#{node['apache']['dir']}/conf.d/nagios3.conf" do
  action :delete
end

case node['nagios']['server_auth_method']
when "openid"
  include_recipe "apache2::mod_auth_openid"
else
  template "#{node['nagios']['conf_dir']}/htpasswd.users" do
    source "htpasswd.users.erb"
    owner node['nagios']['user']
    group node['apache']['user']
    mode 0640
    variables(
      :sysadmins => sysadmins
    )
  end
end

apache_site "000-default" do
  enable false
end

directory "#{node['nagios']['conf_dir']}/certificates" do
  owner node['apache']['user']
  group node['apache']['user']
  mode "700"
end

bash "Create SSL Certificates" do
  cwd "#{node['nagios']['conf_dir']}/certificates"
  code <<-EOH
  umask 077
  openssl genrsa 2048 > nagios-server.key
  openssl req -subj "#{node['nagios']['ssl_req']}" -new -x509 -nodes -sha1 -days 3650 -key nagios-server.key > nagios-server.crt
  cat nagios-server.key nagios-server.crt > nagios-server.pem
  EOH
  not_if { ::File.exists?("#{node['nagios']['conf_dir']}/certificates/nagios-server.pem") }
end

template "#{node['apache']['dir']}/sites-available/nagios3.conf" do
  source "ap2.conf.erb"
  mode 0644
  variables(
    :public_domain => public_domain,
    :servername => node['nagios']['apache_config']['servername'],
    :aliases => node['nagios']['apache_config']['aliases']
  )
  notifies :reload, "service[apache2]"
end

apache_site "nagios3.conf"

%w{ nagios cgi }.each do |conf|
  nagios_conf conf do
    config_subdir false
  end
end

%w{ templates timeperiods}.each do |conf|
  nagios_conf conf
end

#template "/usr/sbin/graphios.py" do
#  source "graphios.py.erb"
#  mode 0755
#end

#template "/etc/init.d/graphios.init" do
#  source "graphios.init.erb"
#  mode 0755
#end

#template "/etc/init/graphios.conf" do
#  source "graphios.conf.erb"
#  mode 0755
#end


begin
  external_sites = data_bag("external_sites")
rescue
  Chef::Log.info("Search for external sites data bag failed, we'll just move on...")
end

exsites = []
external_sites.each do |es|
  #puts data_bag_item('external_sites', es)
  s = data_bag_item('external_sites', es)
  exsites << s
end

puts "Monitoring External Sites:"
puts exsites

if external_sites.nil? || external_sites.empty?
  Chef::Log.info("No external sites returned from search")
  external_sites = Array.new
end

nagios_conf "external_sites" do
  variables(
    :external_sites => exsites,
    :hostgroup_name => "External Sites"
  )
end

begin
  sites = data_bag("sites")
rescue Net::HTTPServerException
  Chef::Log.info("Search for sites data bag failed, so we'll just move on.")
end

if sites.nil? || sites.empty?
  Chef::Log.info("No services returned from data bag search.")
  sites = Array.new
end

insites = []
sites.each do |is|
  s = data_bag_item('sites', is)
  if s['enabled'] = "true"
    insites << s
  else
    puts "#{s['domain']} is disabled"
  end
end
puts "Monitoring Internal Sites:"
puts insites

nagios_conf "sites" do
  variables(
    :sites => insites,
    :hostgroup_name => "Internal Sites"
  )
end

nagios_conf "commands" do
  variables :services => services
end

nagios_conf "services" do
  variables(
    :service_hosts => service_hosts,
    :services => services
  )
end

nagios_conf "contacts" do
  variables :admins => sysadmins, :members => members
end

nagios_conf "hostgroups" do
  variables :roles => role_list
end

nagios_conf "hosts" do
  variables :nodes => nodes
end

service "nagios" do
  service_name node['nagios']['server']['service_name']
  supports :status => true, :restart => true, :reload => true
  action [ :enable, :start ]
end
