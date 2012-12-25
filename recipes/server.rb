#
# Cookbook Name:: cloudfoundry-cloud_controller
# Recipe:: server
#
# Copyright 2012, ZephirWorks
# Copyright 2012, Trotter Cashion
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

include_recipe "postgresql::client"

include_recipe "cloudfoundry-cloud_controller::install_deps"

#
# Install the correct rbenv
#
node.default['cloudfoundry_cloud_controller']['ruby_version'] = node['cloudfoundry']['ruby_1_9_2_version']
ruby_ver = node['cloudfoundry_cloud_controller']['ruby_version']
ruby_path = ruby_bin_path(ruby_ver)

include_recipe "rbenv::default"
include_recipe "rbenv::ruby_build"

rbenv_ruby ruby_ver

#
# Create all the directories we are going to need
#
%w[log_dir].each do |d|
  directory node['cloudfoundry'][d] do
    recursive true
    owner node['cloudfoundry']['user']
    mode  0755
  end
end
%w[data_dir].each do |d|
  directory node['cloudfoundry_cloud_controller'][d] do
    recursive true
    owner node['cloudfoundry']['user']
    mode  '0755'
  end
end
%w[droplets_dir resources_dir staging_manifests_dir tmp_dir].each do |d|
  directory node['cloudfoundry_cloud_controller']['server'][d] do
    recursive true
    owner node['cloudfoundry']['user']
    mode  '0755'
  end
end

#
# Install and configure
#
config_file  = File.join(node['cloudfoundry']['config_dir'], "cloud_controller.yml")
install_path = File.join(node['cloudfoundry_cloud_controller']['vcap']['install_path'], "cloud_controller")

cloudfoundry_source "cloud_controller" do
  path          node['cloudfoundry_cloud_controller']['vcap']['install_path']
  repository    node['cloudfoundry_cloud_controller']['vcap']['repo']
  reference     node['cloudfoundry_cloud_controller']['vcap']['reference']
  subdirectory  "cloud_controller"
end

cloudfoundry_component "cloud_controller" do
  install_path install_path
  bin_file File.join(install_path, "bin", "cloud_controller")
  pid_file node['cloudfoundry_cloud_controller']['server']['pid_file']
  log_file node['cloudfoundry_cloud_controller']['server']['log_file']
  action        [:create, :enable]
  subscribes    :restart, resources(:cloudfoundry_source => "cloud_controller")
end

template File.join(node['cloudfoundry']['config_dir'], "runtimes.yml") do
  source "runtimes.yml.erb"
  owner node['cloudfoundry']['user']
  mode 0644
end

cf_runtimes.each do |_,runtime|
  runtime['frameworks'].each do |framework|
    template File.join(node['cloudfoundry_cloud_controller']['server']['staging_manifests_dir'], "#{framework}.yml") do
      source "#{framework}.yml.erb"
      owner node['cloudfoundry']['user']
      mode 0644
    end
  end
end

bash "run cloudfoundry migrations" do
  user node['cloudfoundry']['user']
  cwd  install_path
  code "PATH=\"#{ruby_path}:$PATH\" #{File.join(ruby_path, "bundle")} exec rake db:migrate RAILS_ENV=production CLOUD_CONTROLLER_CONFIG='#{config_file}'"
  subscribes :run, resources(:cloudfoundry_source => "cloud_controller")
  action :nothing
end
