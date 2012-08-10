ruby_path    = File.join(rbenv_root, "versions", node.cloudfoundry_common.ruby_1_9_2_version, "bin")
config_file  = File.join(node.cloudfoundry_common.config_dir, "cloud_controller.yml")
install_path = File.join(node['cloudfoundry_cloud_controller']['vcap']['install_path'], "cloud_controller")

# Needed because the CloudController Gemfile depends on mysql
include_recipe "mysql::client"

# CloudController must unzip incoming files
package "unzip"
package "zip"

# For the nokogiri dependency
package "libxml2"
package "libxml2-dev"
package "libxslt1-dev"

# For the sqlite3 dependency
package "sqlite3"
package "libsqlite3-dev"

cloudfoundry_common_source "cloud_controller" do
  path          node['cloudfoundry_cloud_controller']['vcap']['install_path']
  repository    node['cloudfoundry_cloud_controller']['vcap']['repo']
  reference     node['cloudfoundry_cloud_controller']['vcap']['reference']
  subdirectory  "cloud_controller"
end

cloudfoundry_common_component "cloud_controller" do
  install_path install_path
  bin_file File.join(install_path, "bin", "cloud_controller")
  pid_file node.cloudfoundry_cloud_controller.server.pid_file
  log_file node.cloudfoundry_cloud_controller.server.log_file
  upstart_file  "upstart-chuid.conf.erb"
  action        [:create, :enable]
  subscribes    :restart, resources("cloudfoundry-common_source" => "cloud_controller")
end

bash "run cloudfoundry migrations" do
  user node[:cloudfoundry_common][:user]
  cwd  install_path
  code "PATH=\"#{ruby_path}:$PATH\" #{File.join(ruby_path, "bundle")} exec rake db:migrate RAILS_ENV=production CLOUD_CONTROLLER_CONFIG='#{config_file}'"
  subscribes :run, resources("cloudfoundry-common_source" => "cloud_controller")
  action :nothing
end

# Write config files for each framework so that cloud_controller can
# detect what kind of application it's dealing with.
if !node[:cloudfoundry_cloud_controller][:server][:frameworks] ||
    node[:cloudfoundry_cloud_controller][:server][:frameworks].empty?
  Chef::Log.info "No frameworks specified, skipping framework configs."
else
  node[:cloudfoundry_cloud_controller][:server][:frameworks].each do |_, framework|
    include_recipe framework[:cookbook]
  end
end

if node[:cloudfoundry_cloud_controller][:server][:use_nginx]
  template File.join(node[:nginx][:dir], "sites-available", "cloud_controller") do
    source "nginx.conf.erb"
    owner  "root"
    group  "root"
    mode   "0644"
    notifies :restart, "service[nginx]"
  end

  nginx_site "cloud_controller" do
    nxpath File.join(node[:nginx][:path], "sbin")
  end

  # nginx recipe adds a default site. It gets in our way, so we remove it.
  nginx_site "default" do
    nxpath File.join(node[:nginx][:path], "sbin")
    enable false
  end
else
  nginx_site "cloud_controller" do
    nxpath File.join(node[:nginx][:path], "sbin")
    enable false
  end
end
