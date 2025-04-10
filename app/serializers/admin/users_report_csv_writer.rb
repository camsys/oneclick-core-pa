module Admin
  class UsersReportCSVWriter < CSVWriter
    columns :email, :first_name, :last_name, 
            :trips_planned, :created_at
    associations :trips, :preferred_locale
    
    def trips_planned
      @record.trips.distinct.count
    end    

  end
end