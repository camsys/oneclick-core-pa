namespace :ecolane do

  desc "Update Ecolane POIs"
  task :update_pois => :environment do

    # Check to see if another instance is already running
    is_already_running = false
    task_run_state = Config.find_or_create_by key: 'ecolane_task_is_running'
    task_run_state.with_lock do
      task_run_state.reload
      is_already_running = task_run_state.value
      # Make sure this isn't an old value that didn't get cleaned up
      if is_already_running && task_run_state.updated_at > (DateTime.now - 1.day)
        puts "Another task instance is already running. Exiting."
        exit
      else
        task_run_state.value = true
        task_run_state.save!
        puts "Running this instance."
      end
    end
    
    messages = []
    local_error = false

    # Ecolane POIs are broken down by system. First, get a list of all the unique Ecolane Systems.
    # Order from oldest to newest.
    systems = []
    services  = []
    Service.paratransit_services.published.is_ecolane.order(:id).each do |service|
      if not service.booking_details[:external_id].blank? and
        not service.booking_details[:external_id].in? systems and
        not service.booking_details[:token].blank? and
        not service.agency.blank?
        systems << service.booking_details[:external_id]
        services << service
        puts "Preparing to sync System: #{service.booking_details[:external_id]}, Service: #{service.id} #{service.name}, Agency: #{service&.agency&.id}"
      end
    end

    puts "starting sync"
    # Get the current POIs and mark them as old
    Landmark.update_all(old: true)
    poi_processed_count = 0
    poi_with_no_city = 0
    poi_blank_name_count = 0
    poi_total_duplicate_count = 0
    
    new_poi_names_set = Set.new
    
    # Group services by Ecolane database and process each group
    services.group_by { |s| s.booking_details[:external_id] }.each do |system, grouped_services|
      begin
        # Get a Hash of new POIs from Ecolane for the first service in the group
        new_poi_hashes = grouped_services.first.booking_ambassador.get_pois
        if new_poi_hashes.nil?
          # If anything goes wrong the new pois will be deleted and the old reinstated
          messages << "Error loading POIs for System: #{system}. Unable to retrieve POIs"
          local_error = true
          puts messages.to_s
          break
        end

        puts "Processing #{new_poi_hashes.count} POIs for #{system}"
        new_poi_duplicate_count = 0
        # Import named pois before unnamed locations
        new_poi_hashes_sorted = new_poi_hashes.sort_by { |h| h[:name].blank? ? 'ZZZZZ' : h[:name] }
        new_poi_hashes_sorted.each do |hash|
          new_poi = Landmark.new hash
          new_poi.old = false
          next if new_poi.city.blank? || new_poi.name =~ /do not use/i

          new_poi.name = new_poi.auto_name if new_poi.name.blank?
          new_poi.search_text = "#{new_poi.name} #{new_poi.auto_name} #{new_poi.zip}"
          next if new_poi_names_set.add?(new_poi.search_text.strip.downcase).nil?

          # Save the POI for each service in the group
          grouped_services.each do |service|
            new_poi_dup = new_poi.dup
            new_poi_dup.agency_id = service&.agency&.id
            new_poi_dup.service_id = service.id
            new_poi_dup.save(validate: false)
          end

          poi_processed_count += 1
          puts "#{poi_processed_count} POIs processed, #{new_poi_duplicate_count} duplicates, #{poi_with_no_city} missing cities" if poi_processed_count % 1000 == 0
        end

      rescue Exception => e
        # If anything goes wrong....
        messages << "Error loading POIs for #{system}. #{e.message}."
        local_error = true
        # Log if errors happen
        puts messages.to_s
        break
      end

      unless local_error
        #If we made it this far, then we have a new set of POIs and we can delete the old ones.
        new_poi_count = new_poi_hashes.count
        messages << "Successfully loaded  #{new_poi_count} POIs with #{new_poi_duplicate_count} duplicates for #{system}."
        poi_total_duplicate_count += new_poi_duplicate_count
      end

    end

    unless local_error
      # If we made it this far, then we have a new set of POIs and we can delete the old ones.
      # Exclude any in use.
      # TODO: For OCC-957, this needs to be updated to match and update POIs in use using mobile API location id.
      landmark_set_landmark_ids = LandmarkSetLandmark.all.pluck(:landmark_id)
      Landmark.is_old.where.not(id: landmark_set_landmark_ids).destroy_all
      Landmark.is_old.where(id: landmark_set_landmark_ids).update_all(old: false)
      new_poi_count = Landmark.count
      messages << "Successfully loaded #{new_poi_count} POIs"
      messages << "count of pois with duplicate names: #{poi_total_duplicate_count}"
      messages << "count of pois with no city: #{poi_with_no_city}"
      messages << "count of pois with initial blank name: #{poi_blank_name_count}"
      puts messages.to_s
    end

  ensure
    task_run_state.update(value: false) unless is_already_running

    if local_error
      # If anything went wrong, delete the new pois and reinstate the old_pois
      Landmark.is_new.delete_all
      Landmark.is_old.update_all(old: false)
    end
    
  end #update_pois

  # [PAMF-751] NOTE: This is all hard-coded, ideally there's be a better way to do this
  desc "Update Waypoints with an incorrect township as the city to the correct city"
  task fix_townships_city: :environment do
    messages = []
    Trip::CORRECTED_CITIES_HASHES.each do |tp|
      puts "Updating waypoints for #{tp[:incorrect]}"
      wps = Waypoint.where(city: tp[:incorrect])
      incorrect_waypoints_length = wps.length
      wps.update_all(city: tp[:correct])
      messages << "Updated #{incorrect_waypoints_length} waypoints with city name of #{tp[:incorrect]} to new city name of #{tp[:correct]}"

      # Correct the Waypoint name if it includes the incorrect township.
      Waypoint.where("name like ?", "%#{tp[:incorrect]}%").map do |wp|
        puts "Updating waypoint name #{wp.name}"
        wp.name.gsub!(tp[:incorrect], tp[:correct])
        wp.save!
      end
    end
    puts messages.to_s
  end

end #ecolane
