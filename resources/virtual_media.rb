actions :mount, :insert, :eject

property :ilos, Array, :required => true
property :iso_uri, String, :required => true, :regex => /^$|^(ht|f)tp:\/\/[A-Za-z0-9]([-.\w:]*[A-Za-z0-9])([A-Za-z0-9\-\.\?,'\/\\\+&;%\$#~=_]*)?(.iso)$/

include ClientHelper

action :insert do
  ilos.each do |ilo|
    client = build_client(ilo)
    cur_val = client.get_virtual_media
    cur_val.each do |key, hash|
      if hash['MediaTypes'].include?('CD') || hash['MediaTypes'].include?('DVD')
        next if client.is_virtual_media_inserted?(key)
        converge_by "Insert ilo #{client.host} Virtual Media Image from '#{iso_uri}'" do
          client.insert_virtual_media(key, iso_uri)
        end
      end
    end
  end
end

action :eject do
  ilos.each do |ilo|
    client = build_client(ilo)
    cur_val = client.get_virtual_media
    cur_val.each do |key, hash|
      if hash['MediaTypes'].include?('CD') || hash['MediaTypes'].include?('DVD')
        next unless client.is_virtual_media_inserted?(key)
        converge_by "Eject ilo #{client.host} Virtual Media" do
          client.eject_virtual_media(key)
        end
      end
    end
  end
end
