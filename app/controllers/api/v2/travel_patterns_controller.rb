module Api
  module V2
    class TravelPatternsController < ApiController
      before_action :require_authentication

      def index
        agency = @traveler.transportation_agency
        service = @traveler.current_service
        purpose = query_params.delete(:purpose)
        funding_source_names = @traveler.get_funding_data(service)[purpose] if purpose
        date = query_params.delete(:date)
        query_params[:agency] = agency
        query_params[:service] = service
        query_params[:purpose] = Purpose.find_or_initialize_by(agency: agency, name: purpose.strip) if purpose
        query_params[:funding_sources] = FundingSource.where(name: funding_source_names) if purpose # Only filter funding sources if a purpose is present
        query_params[:date] = Date.strptime(query_params[:date], '%Y-%m-%d') if date
        Rails.logger.info("Filtering through Travel Patterns with the following filters: #{query_params}")
        travel_patterns = TravelPattern.available_for(query_params)
        if purpose
          Rails.logger.info("Looking for the valid date range for purpose: #{purpose}")
          booking_profile = @traveler.booking_profiles.first
          if booking_profile
            begin
              trip_purposes, trip_purposes_hash = booking_profile.booking_ambassador.get_trip_purposes
              puts "Trip Purposes Count: #{trip_purposes.count}"
              puts "Trip Purposes Hash Count: #{trip_purposes_hash.count}"
            rescue Exception => e
              trip_purposes = []
              trip_purposes_hash = []
            end
            trip_purpose_hash = trip_purposes_hash
              .select { |h| h[:code] == purpose }
              .delete_if { |h| h[:valid_from].nil? }
              .min_by { |h| h[:valid_from] }

            if trip_purpose_hash
              valid_from = trip_purpose_hash[:valid_from]
              valid_until = trip_purpose_hash[:valid_until]
              Rails.logger.info("Valid From: #{valid_from}, Valid Until: #{valid_until}")
            else
              Rails.logger.info("No valid date range found for purpose: #{purpose}")
            end
          end
        
          # Cross-reference funding sources for each travel pattern, ensuring both conditions are met
          valid_patterns = travel_patterns.select do |pattern|
            Rails.logger.info "Checking Travel Pattern ID: #{pattern.id}"
            Rails.logger.info "Funding sources for travel pattern: #{pattern.funding_sources.pluck(:name)}"
            Rails.logger.info "Funding sources from Ecolane: #{funding_source_names}"
            
            # Step 1: Check that funding sources match between Ecolane and the travel pattern
            if pattern.funding_sources.present? && funding_source_names.present?
              matching_funding_sources = pattern.funding_sources.select do |fs|
                funding_source_names.include?(fs.name)
              end

              # Step 2: Validate the date range if matching funding sources are found
              if matching_funding_sources.any? && valid_from && valid_until
                current_date = Date.today
                valid_date_range = (valid_from <= current_date) && (valid_until >= current_date)
                Rails.logger.info "Valid date range: #{valid_date_range} (from #{valid_from} to #{valid_until})"
                
                # Allow only if both funding source and date range are valid
                valid = valid_date_range
                Rails.logger.info "Match found and date range is valid: #{valid}"
                valid
              else
                Rails.logger.info "No valid date range or matching funding sources for Travel Pattern ID: #{pattern.id}"
                false
              end
            else
              Rails.logger.info "No valid funding sources found for Travel Pattern ID: #{pattern.id}"
              false
            end
          end

          if valid_patterns.any?
            Rails.logger.info("Found the following matching Travel Patterns: #{valid_patterns.map { |t| t['id'] }}")
            api_response = valid_patterns.map { |pattern| TravelPattern.to_api_response(pattern, service, valid_from, valid_until) }
            render status: :ok, json: {
              status: "success",
              data: api_response
            }
          else
            Rails.logger.info("No matching Travel Patterns found")
            render fail_response(status: 404, message: "Not found")
          end
        else
          # If no purpose, just return all available travel patterns without further filtering
          if travel_patterns.any?
            api_response = travel_patterns.map { |pattern| TravelPattern.to_api_response(pattern, service) }
            render status: :ok, json: {
              status: "success",
              data: api_response
            }
          else
            render fail_response(status: 404, message: "Not found")
          end
        end
      end
      protected

      def query_params
        @query ||= params.permit(
          :purpose,
          :date,
          :start_time,
          :end_time,
          origin: [:lat, :lng],
          destination: [:lat, :lng]
        )
      end

    end
  end
end
