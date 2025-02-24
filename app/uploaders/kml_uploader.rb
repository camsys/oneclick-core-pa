# Helper class for uploading a KML file and reading it.
class KMLUploader
  require 'geospatial/kml/reader'

  attr_reader :errors, :custom_geo, :warnings

  # Initialize with a path to a KML file
  def initialize(file, opts={})
    @file = file
    @path = opts[:path] || @file.tempfile.path
    # NOTE: the name field is specific to Travel Patterns
    @name = opts[:name]
    @agency = opts[:agency].present? ? Agency.find(opts[:agency]) : nil
    @filetype = opts[:content_type] || @file.content_type
    @model = opts[:geo_type].to_s.classify.constantize
    @column_mappings = opts[:column_mappings] || {name: 'NAME', state: 'STATEFP'}
    @errors = []
    @custom_geo = nil
    @warnings = []
    Rails.logger.info "KMLUploader initialized with file type: #{@filetype}, name: #{@name}, agency: #{@agency.try(:id)}, model: #{@model}"
  end

  # Call load to process the uploaded filepath into geometric database records
  def load
    @errors.clear
    Rails.logger.info "Opening file at path: #{@path}..."
    if @filetype == "application/vnd.google-earth.kml+xml" || @filetype == "application/octet-stream"
      Rails.logger.info "File type valid (#{@filetype}). Proceeding with load_kmlfile."
      load_kmlfile(@path)
    else
      Rails.logger.error "Invalid file type detected: #{@filetype}"
      @errors << "Please upload a .kml file."
    end
    Rails.logger.info "Load completed. Errors: #{@errors.inspect}, Warnings: #{@warnings.inspect}"
    return self
  end

  def successful?
    @errors.empty?
  end

  private

  def load_kmlfile(file_name)
    Rails.logger.info "Reading Shapes into #{@model.to_s} Table from file: #{file_name}..."
    begin
      reader = Geospatial::KML::Reader.load_file(@path)
      polygon_count = reader.polygons.count
      Rails.logger.info "Total polygons found in KML: #{polygon_count}"
      reader.polygons do |polygon|
        Rails.logger.info "Processing a new polygon: #{polygon.inspect}"
        fail_count = 0
        Rails.logger.info "Current model: #{@model.name}, expected: #{CustomGeography.name}"
        Rails.logger.info "Dashboard mode is: #{Config.dashboard_mode}"
        if @model.name == CustomGeography.name && Config.dashboard_mode == 'travel_patterns'
          Rails.logger.info "Inside travel_patterns block for record creation."
          attrs = {}
          if polygon_count > 1
            Rails.logger.warn "Multiple features detected (#{polygon_count}); uploader only accepts one feature."
            @warnings << 'Found multiple features while creating a custom geography. Uploader only accepts one feature'
          else
            Rails.logger.info "Single feature detected; proceeding to load record for #{@name}."
            polygon_points = []
            polygon.points.each do |point|
              point_str = [point[0], point[1]].join(" ")
              Rails.logger.info "Processing point: #{point_str}"
              polygon_points.push(point_str.to_s)
            end
            polygon_wkt = 'POLYGON((' + polygon_points.join(", ") + '))'
            Rails.logger.info "Constructed WKT: #{polygon_wkt}"
            factory = RGeo::ActiveRecord::SpatialFactoryStore.instance.default
            polygon_geom = factory.parse_wkt(polygon_wkt)
            output_geom = factory.multi_polygon([]).union(polygon_geom)
            geom = RGeo::Feature.cast(output_geom, RGeo::Feature::MultiPolygon)
            Rails.logger.info "Parsed geometry: #{geom.as_text}" if geom.respond_to?(:as_text)
            record = ActiveRecord::Base.logger.silence do
              Rails.logger.info "Creating record for CustomGeography with name: #{@name}, agency: #{@agency.try(:id)}"
              @custom_geo = @model.create({ name: @name, agency: @agency })
              Rails.logger.info "Record after create: #{@custom_geo.inspect}"
              @custom_geo.update_attributes(geom: geom)
              Rails.logger.info "Record after updating geom: #{@custom_geo.inspect}"
              if @custom_geo.errors.present?
                Rails.logger.error "Encountered errors: #{@custom_geo.errors.full_messages.to_sentence}"
                @errors << "#{@custom_geo.errors.full_messages.to_sentence} for #{@custom_geo.name}."
              else
                @custom_geo
              end
            end
          end
          if record
            Rails.logger.info "SUCCESS! Record created successfully."
          else
            Rails.logger.error "FAILED to create record."
            fail_count += 1
          end
          @errors << "#{fail_count} record(s) failed to load." if fail_count > 0
        else
          Rails.logger.info "Skipping record creation because model/dashboard mode conditions are not met."
        end
      end
    rescue StandardError => ex
      Rails.logger.error "Exception encountered in load_kmlfile: #{ex.message}"
      puts ex.message
      @errors << "An error occurred while unpacking the uploaded KML file. Please double check your KML file and try again"
    end
  end

end
