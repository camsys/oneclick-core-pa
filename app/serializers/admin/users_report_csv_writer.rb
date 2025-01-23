module Admin
  class UsersReportCSVWriter < CSVWriter
    columns :email, :first_name, :last_name, 
            :accommodations, :trips_planned, :paratransit_id, :created_at
    associations :accommodations, :confirmed_eligibilities, :trips, :preferred_locale   

    def accommodations
      @record.accommodations.pluck(:code).join(', ')
    end
    
    def trips_planned
      @record.trips.joins(:ecolane_booking_snapshot).distinct.count
    end    
  end
end