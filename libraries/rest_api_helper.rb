require 'pry'
require 'base64'
require 'net/http'
require 'time'
require 'yaml'

module RestAPI
  module Helper
    include Chef::Mixin::ShellOut

    def adminhref(uad, userName)
      minhref=nil
      uad["Items"].each do |account|
        if account["UserName"] == userName
          minhref=account["links"]["self"]["href"]
          return minhref
        end
      end
      fail "Could not find user account #{userName}"
    end

    def rest_api(type, path, machine, options = {})
      disable_ssl = true
      uri = URI.parse(URI.escape(machine['ilo_site'] + path))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if disable_ssl
      case type.downcase
      when 'get', :get
        request = Net::HTTP::Get.new(uri.request_uri)
      when 'post', :post
        request = Net::HTTP::Post.new(uri.request_uri)
      when 'put', :put
        request = Net::HTTP::Put.new(uri.request_uri)
      when 'delete', :delete
        request = Net::HTTP::Delete.new(uri.request_uri)
      when 'patch', :patch
        request = Net::HTTP::Patch.new(uri.request_uri)
      else
        fail "Invalid rest call: #{type}"
      end
      options['Content-Type'] ||= 'application/json'
      options.each do |key, val|
        if key.downcase == 'body'
          request.body = val.to_json rescue val
        else
          request[key] = val
        end
      end
      request.basic_auth(machine["username"], machine["password"])
      response = http.request(request)
      JSON.parse(response.body) rescue response
    end

    def reset_user_password(machine, modUserName, modPassword)
      #User account information
      uad = rest_api(:get, '/rest/v1/AccountService/Accounts', machine)
      #User account url
      userhref = adminhref(uad, modUserName)
      options = {
        'body' => modPassword
      }
      rest_api(:patch, userhref, machine, options)
    end

    def delete_user(deleteUserName, machine)
      uad = rest_api(:get, '/rest/v1/AccountService/Accounts', machine)
      minhref = adminhref(uad, deleteUserName )
      rest_api(:delete, minhref, machine)
    end

    def reset_server(machine)
      newAction = {"Action"=> "Reset", "ResetType"=> "ForceRestart"}
      options = {'body' => newAction}
      sysget = rest_api(:get, '/rest/v1/systems', machine)
      sysuri = sysget["links"]["Member"][0]["href"]
      rest_api(:post, sysuri, machine, options)
    end

    def power_on(machine)
      newAction = {"Action"=> "Reset", "ResetType"=> "On"}
      options = {'body' => newAction}
      sysget = rest_api(:get, '/rest/v1/systems', machine)
      sysuri = sysget["links"]["Member"][0]["href"]
      rest_api(:post, sysuri, machine, options)
    end

    def power_off(machine)
      newAction = {"Action"=> "Reset", "ResetType"=> "ForceOff"}
      options = {'body' => newAction}
      sysget = rest_api(:get, '/rest/v1/systems', machine)
      sysuri = sysget["links"]["Member"][0]["href"]
      rest_api(:post, sysuri, machine, options)
    end


    def findILOMacAddr(machine)
      iloget = rest_api(:get, '/rest/v1/Managers/1/NICs', machine)
      iloget["Items"][0]["MacAddress"]
    end

    def resetILO(machine)
      newAction = {"Action"=> "Reset"}
      options = {'body' => newAction}
      mgrget = rest_api(:get, '/rest/v1/Managers', machine)
      mgruri = mgrget["links"]["Member"][0]["href"]
      rest_api(:post, mgruri ,machine ,options )
    end

    def create_user(machine,username,password)
      rest_api(:get, '/rest/v1/AccountService/Accounts', machine)
      newUser = {"UserName" => username, "Password"=> password, "Oem" => {"Hp" => {"LoginName" => username} }}
      options = {'body' => newUser}
      rest_api(:post, '/rest/v1/AccountService/Accounts', machine,  options)
    end

    def fw_upgrade(machine,uri)
      newAction = {"Action"=> "InstallFromURI", "FirmwareURI"=> uri}
      options = {'body' => newAction}
      rest_api(:post, '/rest/v1/Managers/1/UpdateService', machine, options)
    end

    def apply_license(machine, license_key)
      newAction = {"LicenseKey"=> license_key}
      options = {'body' => newAction}
      rest_api(:post, '/rest/v1/Managers/1/LicenseService/1', machine, options )
    end

    def clear_iel_logs(machine)
      newAction = {"Action"=> "ClearLog"}
      options = {'body' => newAction}
      rest_api(:post, '/rest/v1/Managers/1/LogServices/IEL', machine, options)
    end

    def clear_iml_logs(machine)
      newAction = {"Action"=> "ClearLog"}
      options = {'body' => newAction}
      rest_api(:post, '/rest/v1/Systems/1/LogServices/IML', machine, options)
    end

    def dump_iel_logs(machine,ilo,severity_level,file,duration)
      entries = rest_api(:get, '/rest/v1/Managers/1/LogServices/IEL/Entries', machine)["links"]["Member"]
      severity_level = "OK" || "Warning" || "Critical" if severity_level == "any"
      entries.each do |e|
        logs = rest_api(:get, e["href"], machine)
        severity = logs["Severity"]
        message = logs["Message"]
        created = logs["Created"]
        ilo_log_entry = "#{ilo} | #{severity} | #{message} | #{created} \n" if severity == severity_level and Time.parse(created) > (Time.parse(created) - (duration*3600))
        File.open("#{Chef::Config[:file_cache_path]}/#{file}.txt", 'a+') {|f| f.write(ilo_log_entry) }
      end
    end

    def dump_iml_logs(machine, ilo, severity_level,file,duration)
      entries = rest_api(:get, '/rest/v1/Systems/1/LogServices/IML/Entries', machine)["links"]["Member"]
      severity_level = "OK" || "Warning" || "Critical" if severity_level == "any"
      entries.each do |e|
        logs = rest_api(:get, e["href"], machine)
        severity = logs["Severity"]
        message = logs["Message"]
        created = logs["Created"]
        ilo_log_entry = "#{ilo} | #{severity} | #{message} | #{created} \n" if severity == severity_level and Time.parse(created) > (Time.parse(created) - (duration))
        File.open("#{Chef::Config[:file_cache_path]}/#{file}.txt", 'a+') {|f| f.write(ilo_log_entry) }
      end
    end

    def enable_uefi_secure_boot(machine, value)
      newAction = {"SecureBootEnable"=> value}
      options = {'body' => newAction}
      rest_api(:patch, '/rest/v1/Systems/1/SecureBoot', machine, options)
    end

    def revert_bios_settings(machine)
      newAction = {"BaseConfig" => "default"}
      options = {'body' => newAction}
      rest_api(:put, '/rest/v1/Systems/1/BIOS/Settings',machine,options)
    end

    def reset_boot_order(machine)
      newAction = {"RestoreManufacturingDefaults" => "yes"}
      options = {'body' => newAction}
      rest_api(:patch, '/rest/v1/Systems/1/BIOS',machine,options)
    end

    def set_ilo_time_zone(machine, time_zone_index)
      timezone = rest_api(:get, '/rest/v1/Managers/1/DateTime',machine)
      puts "Current TimeZone is: " + timezone["TimeZone"]["Name"]
      newAction = {"TimeZone" => {"Index" => time_zone_index}}
      options = {'body' => newAction}
      out = rest_api(:patch, '/rest/v1/Managers/1/DateTime', machine, options)
      raise "SNTP Configuration is managed by DHCP and is read only" if out["Messages"][0]["MessageID"] ==  "iLO.0.10.SNTPConfigurationManagedByDHCPAndIsReadOnly"
      timezone = rest_api(:get, '/rest/v1/Managers/1/DateTime',machine)
      puts "TimeZone set to: " + timezone["TimeZone"]["Name"]
    end

    def use_ntp_servers(machine,value)
      newAction = {"Oem" => {"Hp" => {"DHCPv4" => {"UseNTPServers" => value}}}}
      options = {'body' => newAction}
      rest_api(:patch, '/rest/v1/Managers/1/EthernetInterfaces/1',machine,options)
    end

    def set_led_light(machine, state)
      newAction = {"IndicatorLED" => "Lit"}
      options = {'body' => newAction}
      rest_api(:patch, '/rest/v1/Systems/1',machine,options)
    end

    def dump_computer_details(machine,file)
      general_details = rest_api(:get, '/rest/v1/Systems/1',machine)
      manufacturer = general_details["Manufacturer"]
      model = general_details["Model"]
      asset_tag = general_details['AssetTag']
      bios_version = general_details['Bios']['Current']['VersionString']
      memory = general_details['Memory']['TotalSystemMemoryGB'].to_s + ' GB'
      processors = general_details['Processors']['Count'].to_s + ' x ' + general_details['Processors']['ProcessorFamily'].to_s
      details = {
        "#{machine['ilo_site']}" => {
          'manufacturer' => manufacturer,
          'model' => model,
          'AssetTag' => asset_tag,
          'bios_version' => bios_version,
          'memory' => memory,
          'processors' => processors}
        }

        network_adapters = []
        networks =  rest_api(:get, rest_api(:get, '/rest/v1/Systems/1',machine)['Oem']['Hp']['links']['NetworkAdapters']['href'], machine)["links"]["Member"]
        networks.each do |network|
          network_detail = rest_api(:get, network["href"],machine)
          physical_ports = []
          network_detail['PhysicalPorts'].each do |port|
            n = {
              'Name' => port['Name'],
              'StructuredName' => port['Oem']['Hp']['StructuredName'],
              'MacAddress' => port['MacAddress'],
              'State' => port['Status']['State']
            }
            physical_ports.push(n)
          end
          nets = {'Name' => network_detail['Name'],
            'StructuredName' => network_detail['StructuredName'],
            'PartNumber'  =>  network_detail['PartNumber'],
            'State' => network_detail['Status']['State'],
            'Health' => network_detail['Status']['Health'],
            'PhysicalPorts' => physical_ports
          }
          network_adapters.push(nets)
        end
        net_adapters = {'NetworkAdapters' => network_adapters }


        storages = rest_api(:get, rest_api(:get, '/rest/v1/Systems/1',machine)['Oem']['Hp']['links']['SmartStorage']['href'], machine)
        array_controllers = []
        array_ctrls = rest_api(:get, storages['links']['ArrayControllers']['href'],machine)
        if array_ctrls["links"].has_key?("Member")
          array_ctrls["links"]["Member"].each do |array_controller|
            controller = rest_api(:get, array_controller["href"],machine)

            storage_enclosures = []
            rest_api(:get, controller["links"]["StorageEnclosures"]["href"], machine)["links"]["Member"].each do |enclosure|
              enclsr = rest_api(:get, enclosure["href"], machine)
              enc = {
                'Model' => enclsr['Model'],
                'SerialNumber' => enclsr['SerialNumber'],
                'DriveBayCount' => enclsr['DriveBayCount'],
                'State' => enclsr['Status']['State'],
                'Health' => enclsr['Status']['Health'],
                'Location' => enclsr['Location'].to_s + ' (' + enclsr['LocationFormat'].to_s + ')',
                'FIrmwareVersion' => enclsr['FirmwareVersion']['Current']['VersionString']
              }
              storage_enclosures.push(enc)
            end

            logical_drives = []
            rest_api(:get, controller["links"]["LogicalDrives"]["href"],machine)["links"]["Member"].each do |logicaldrive|
              lds = rest_api(:get, logicaldrive["href"], machine)
              data_drives = []
              rest_api(:get, lds['links']['DataDrives']['href'],machine)["links"]["Member"].each do |datadrives|
                disk_drive = rest_api(:get,datadrives["href"],machine)
                dsk_drive = {
                  'Model' => disk_drive['Model'],
                  'Name' => disk_drive['Name'],
                  'RotationalSpeedRpm' => disk_drive['RotationalSpeedRpm'],
                  'SerialNumber' => disk_drive['SerialNumber'],
                  'State' => disk_drive['Status']['State'],
                  'Health' => disk_drive['Status']['Health'],
                  'CapacityMiB' => disk_drive['CapacityMiB'],
                  'CurrentTemperatureCelsius' => disk_drive['CurrentTemperatureCelsius']
                }
                data_drives.push(dsk_drive)
              end
              ld = {
                'Size' => lds['CapacityMiB'],
                'Raid' => lds['Raid'],
                'Status' => lds['Status']['State'],
                'Health' => lds['Status']['Health'],
                'DataDrives' => data_drives
              }
              logical_drives.push(ld)
            end
            ac = {
              'Model' => controller['Model'],
              'SerialNumber' => controller['SerialNumber'],
              'State' => controller['Status']['State'],
              'Health' => controller['Status']['Health'],
              'Location' => controller['Location'],
              'FirmWareVersion' => controller['FirmwareVersion']['Current']['VersionString'],
              'LogicalDrives' => logical_drives,
              'Enclosures' => storage_enclosures
            }
            array_controllers.push(ac)
          end
        end

        hp_smart_storage = {'HPSmartStorage' =>   {
          'Health' => storages['Status']['Health'],
          'ArrayControllers' => array_controllers
        }
      }

      file = File.open("#{Chef::Config[:file_cache_path]}/#{file}.txt", 'a+')
      file.write(details.merge(net_adapters).merge(hp_smart_storage).to_yaml)
      file.write("\n")
      file.close
    end

    def mount_virtual_media(machine, iso_uri, boot_on_next_server_reset)
      rest_api(:get, '/rest/v1/Managers/1/VirtualMedia', machine)["links"]["Member"].each do |vm|
        virtual_media = rest_api(:get,vm["href"],machine)
        next if !(virtual_media["MediaTypes"].include?("CD") || virtual_media["MediaTypes"].include?("DVD"))
        mount = {'Image' =>  iso_uri}
        mount['Oem'] = {'Hp' =>  {'BootOnNextServerReset' =>  boot_on_next_server_reset}}
        newAction = mount
        options = {'body' => newAction}
        rest_api(:patch,vm["href"],machine,options)
      end
    end

    def set_asset_tag(machine,tag)
      newAction = {"AssetTag" => tag}
      options = {'body' => newAction}
      binding.pry
      rest_api(:patch,'/rest/v1/Systems/1',machine,options)
    end
  end
end