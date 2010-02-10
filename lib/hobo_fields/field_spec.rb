module HoboFields

  class FieldSpec

    class UnknownSqlTypeError < RuntimeError; end

    def initialize(model, name, type, options={})
      raise ArgumentError, "you cannot provide a field spec for the primary key" if name == model.primary_key
      self.model = model
      self.name = name.to_sym
      self.type = type.is_a?(String) ? type.to_sym : type
      position = options.delete(:position)
      self.options = options
      self.position = position || model.field_specs.length
    end

    attr_accessor :model, :name, :type, :position, :options

    TYPE_SYNONYMS = [[:timestamp, :datetime]]

    begin
      MYSQL_COLUMN_CLASS = ActiveRecord::ConnectionAdapters::MysqlColumn
    rescue NameError
      MYSQL_COLUMN_CLASS = NilClass
    end

    begin
      SQLITE_COLUMN_CLASS = ActiveRecord::ConnectionAdapters::SQLiteColumn
    rescue NameError
      SQLITE_COLUMN_CLASS = NilClass
    end

    def sql_type
      options[:sql_type] or begin
                              if native_type?(type)
                                type
                              else
                                field_class = HoboFields.to_class(type)
                                field_class && field_class::COLUMN_TYPE or raise UnknownSqlTypeError, "#{type.inspect} for #{model}.#{name}"
                              end
                            end
    end

    def limit
      options[:limit] || native_types[sql_type][:limit]
    end

    def precision
      options[:precision]
    end

    def scale
      options[:scale]
    end

    def null
      options.include?(:null) ? options[:null] : true
    end

    def default
      options[:default]
    end

    def same_type?(col_spec)
      t = sql_type
      TYPE_SYNONYMS.each do |synonyms|
        if synonyms.include? t
          return synonyms.include? col_spec.type
        end
      end
      t == col_spec.type
    end


    def different_to?(col_spec)
      !same_type?(col_spec) ||
        begin
          check_attributes = [:null, :default]
          check_attributes += [:precision, :scale] if sql_type == :decimal && !col_spec.is_a?(SQLITE_COLUMN_CLASS)  # remove when rails fixes https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets/2872
          check_attributes -= [:default] if sql_type == :text && col_spec.is_a?(MYSQL_COLUMN_CLASS)
          check_attributes << :limit if [:string, :text, :binary, :integer].include?(sql_type)
          check_attributes.any? do |k|
            if k==:default && sql_type==:datetime
              dt1 = col_spec.default.respond_to?(:to_datetime) ? col_spec.default.to_datetime : nil
              dt2 = default.respond_to?(:to_datetime) ? default.to_datetime : nil
              dt1 != dt2
            else
              col_spec.send(k) != self.send(k)
            end
          end
        end
    end


    private

    def native_type?(type)
      type != :primary_key && native_types.keys.include?(type)
    end

    def native_types
      MigrationGenerator.native_types
    end

  end

end
