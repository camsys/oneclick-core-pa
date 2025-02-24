module Admin
  class BookingSnapshotsReportCSVWriter < CSVWriter
    columns :trip_id, :negotiated_pu, :traveler, :purpose, :orig_addr, :orig_lat, :orig_lng,
            :dest_addr, :dest_lat, :dest_lng, :agency_name, :service_name, :booking_id,
            :booking_client_id, :is_round_trip, :created_at, :funding_source, :sponsor, :companions,
            :note, :ecolane_error_message, :pca

    def trip_id
      @record.trip_id
    end

    def negotiated_pu
      @record.negotiated_pu || 'No Trip Time'
    end

    def traveler
      @record.traveler || 'No Traveler'
    end

    def purpose
      @record.purpose || 'N/A'
    end

    def orig_addr
      @record.orig_addr || 'No Origin Address'
    end

    def orig_lat
      @record.orig_lat || 'No Origin Latitude'
    end

    def orig_lng
      @record.orig_lng || 'No Origin Longitude'
    end

    def dest_addr
      @record.dest_addr || 'No Destination Address'
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

    def created_at
      @record.created_at.strftime("%Y-%m-%d %H:%M:%S")
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

    def note
      @record.note || ' '
    end

    def ecolane_error_message
      @record.ecolane_error_message || 'N/A'
    end

    def pca
      @record.pca ? 'TRUE' : 'FALSE'
    end
  end
end
