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
  end

  # Call load to process the uploaded filepath into geometric database records
  def load
    @errors.clear
    Rails.logger.info "Opening file..."
    if @filetype == "application/vnd.google-earth.kml+xml" || @filetype == "application/octet-stream"
      load_kmlfile(@path)
    else
      @errors << "Please upload a .kml file."
    end
    return self
  end

  def successful?
    @errors.empty?
  end

  private

  def load_kmlfile(file_name)
    Rails.logger.info "Reading Shapes into #{@model} Table..."
    begin
      reader = Geospatial::KML::Reader.load_file(@path)
    if reader.polygons.any?
      reader.polygons do |polygon|
        fail_count = 0
        if @model.name == CustomGeography.name && Config.dashboard_mode == 'travel_patterns'
          if reader.polygons.count > 1
            @warnings << 'Found multiple features while creating a custom geography. Uploader only accepts one feature'
          else
            Rails.logger.info "Loading #{@name}..."
            polygon_points = []
            polygon.points.each do |point|
              polygon_points.push([point[0], point[1]].join(" "))
            end
            polygon_wkt = 'POLYGON((' + polygon_points.join(", ") + '))'
            factory = RGeo::ActiveRecord::SpatialFactoryStore.instance.default
            polygon_geom = factory.parse_wkt(polygon_wkt)
            output_geom = factory.multi_polygon([]).union(polygon_geom)
            geom = RGeo::Feature.cast(output_geom, RGeo::Feature::MultiPolygon)
            record = ActiveRecord::Base.logger.silence do
              @custom_geo = @model.create({ name: @name, agency: @agency })
              @custom_geo.update_attributes(geom: geom)
              if @custom_geo.errors.present?
                @errors << "#{@custom_geo.errors.full_messages.to_sentence} for #{@custom_geo.name}."
              else
                @custom_geo
              end
            end
          end
          if record
            Rails.logger.info " SUCCESS!"
          else
            Rails.logger.info " FAILED."
            fail_count += 1
          end
          @errors << "#{fail_count} record(s) failed to load." if fail_count > 0
        end
      end
    elsif reader.respond_to?(:linestrings) && reader.linestrings.any?
        # If no polygons, use the first LineString and convert it to a polygon
        linestring = reader.linestrings.first
        points = linestring.points
        points << points.first unless points.first == points.last
        polygon_points = points.map { |point| [point[0], point[1]].join(" ") }
        polygon_wkt = 'POLYGON((' + polygon_points.join(", ") + '))'
        factory = RGeo::ActiveRecord::SpatialFactoryStore.instance.default
        polygon_geom = factory.parse_wkt(polygon_wkt)
        output_geom = factory.multi_polygon([]).union(polygon_geom)
        geom = RGeo::Feature.cast(output_geom, RGeo::Feature::MultiPolygon)
        if @model.name == CustomGeography.name && Config.dashboard_mode == 'travel_patterns'
          record = ActiveRecord::Base.logger.silence do
            @custom_geo = @model.create({ name: @name, agency: @agency })
            @custom_geo.update_attributes(geom: geom)
            if @custom_geo.errors.present?
              @errors << "#{@custom_geo.errors.full_messages.to_sentence} for #{@custom_geo.name}."
            else
              @custom_geo
            end
          end
          if record
            Rails.logger.info " SUCCESS!"
          else
            Rails.logger.info " FAILED."
          end
        end
      else
        @errors << "No valid polygon or linestring features found in the KML file."
      end
    rescue StandardError => ex
      puts ex.message
      @errors << "An error occurred while unpacking the uploaded KML file. Please double check your KML file and try again"
    end
  end

end
