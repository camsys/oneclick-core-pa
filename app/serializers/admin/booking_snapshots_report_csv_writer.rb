module Admin
  class BookingSnapshotsReportCSVWriter < CSVWriter
    columns :trip_time, :traveler, :disposition_status, :purpose,
            :orig_lat, :orig_lng, :dest_lat, :dest_lng, :agency_name, :service_name,
            :booking_id, :booking_client_id, :is_round_trip, :booking_timestamp,
            :ecolane_error_message, :funding_source, :sponsor, :companions, :trip_note,
            :pca, :orig_addr, :dest_addr

    def trip_time
      @record.negotiated_pu || 'No Trip Time'
    end

    def traveler
      @record.traveler || 'No Traveler'
    end

    def disposition_status
      @record.disposition_status || 'Unknown Disposition'
    end

    def purpose
      @record.purpose || 'N/A'
    end

    def orig_lat
      @record.orig_lat || 'No Origin Latitude'
    end

    def orig_lng
      @record.orig_lng || 'No Origin Longitude'
    end

    def dest_lat
      @record.dest_lat || 'No Destination Latitude'
    end

    def dest_lng
      @record.dest_lng || 'No Destination Longitude'
    end

    def agency_name
      @record.agency_name || 'No Agency'
    end

    def service_name
      @record.service_name || 'No Service'
    end

    def booking_id
      @record.booking_id || 'No Booking ID'
    end

    def booking_client_id
      @record.booking_client_id || 'No Booking Client ID'
    end

    def is_round_trip
      @record.is_round_trip ? 'TRUE' : 'FALSE'
    end

    def booking_timestamp
      @record.created_at.strftime("%Y-%m-%d %H:%M:%S")
    end

    def ecolane_error_message
      @record.ecolane_error_message || 'N/A'
    end

    def funding_source
      @record.funding_source || 'No Funding Source'
    end

    def sponsor
      @record.sponsor || 'No Sponsor'
    end

    def companions
      @record.companions || '0'
    end

    def trip_note
      @record.note || ' '
    end

    def pca
      @record.pca ? 'TRUE' : 'FALSE'
    end

    def orig_addr
      @record.orig_addr || 'No Origin Address'
    end

    def dest_addr
      @record.dest_addr || 'No Destination Address'
    end
  end
end
