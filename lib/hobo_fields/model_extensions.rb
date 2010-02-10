module HoboFields

  module ModelExtensions
    def self.included(base)
      base.extend ClassMethods
      base.class_eval do
        class << self
          alias_method_chain :attr_accessor, :rich_types
          alias_method_chain :belongs_to, :field_declarations
          alias_method_chain :acts_as_list,  :field_declaration if defined?(ActiveRecord::Acts::List)
        end
      end
    end

    module ClassMethods
      # ignore the model in the migration until somebody sets
      # @include_in_migration via the fields declaration
      attr_reader :include_in_migration

      # attr_types holds the type class for any attribute reader (i.e. getter
      # method) that returns rich-types
      def attr_types
        @attr_types ||= HashWithIndifferentAccess.new
      end
      def attr_order
        @attr_order ||= []
      end

      # field_specs holds FieldSpec objects for every declared
      # field. Note that attribute readers are created (by ActiveRecord)
      # for all fields, so there is also an entry for the field in
      # attr_types. This is redundant but simplifies the implementation
      # and speeds things up a little.
      def field_specs
        @field_specs ||= HashWithIndifferentAccess.new
      end

      # index_specs holds IndexSpec objects for all the declared indexes.
      def index_specs
        @index_specs ||= []
      end
      def ignore_indexes
        @ignore_indexes ||= []
      end

      def inherited(klass)
        fields do |f|
          f.field(inheritance_column, :string)
        end
        index(inheritance_column)
        super
      end

      def index(fields, options = {})
        # don't double-index fields
        ffs = Array.wrap(fields).map { |f| f.to_s }
        unless index_specs.find { |s| s.fields.include?(ffs) }
          index_specs << HoboFields::IndexSpec.new(self, fields, options)
        end
      end

      # tell the migration generator to ignore the named index. Useful for existing indexes, or for indexes
      # that can't be automatically generated (for example: an prefix index in MySQL)
      def ignore_index(index_name)
        ignore_indexes << index_name.to_s
      end

      public

      # Declares that a virtual field that has a rich type (e.g. created
      # by attr_accessor :foo, :type => :email_address) should be subject
      # to validation (note that the rich types know how to validate themselves)
      def validate_virtual_field(*args)
        validates_each(*args) {|record, field, value| msg = value.validate and record.errors.add(field, msg) if value.respond_to?(:validate) }
      end


      # This adds a ":type => t" option to attr_accessor, where t is
      # either a class or a symbolic name of a rich type. If this option
      # is given, the setter will wrap values that are not of the right
      # type.
      def attr_accessor_with_rich_types(*attrs)
        options = attrs.extract_options!
        type = options.delete(:type)
        attrs << options unless options.empty?
        public
        attr_accessor_without_rich_types(*attrs)
        private

        if type
          type = HoboFields.to_class(type)
          attrs.each do |attr|
            declare_attr_type attr, type, options
            type_wrapper = attr_type(attr)
            define_method "#{attr}=" do |val|
              if !HoboFields::PLAIN_TYPES.values.include?(type_wrapper) && !val.is_a?(type) && HoboFields.can_wrap?(type, val)
                val = type.new(val.to_s)
              end
              instance_variable_set("@#{attr}", val)
            end
          end
        end
      end


      # Extend belongs_to so that it creates a FieldSpec for the foreign key
      def belongs_to_with_field_declarations(name, options={}, &block)
        column_options = {}
        column_options[:null] = options.delete(:null) if options.has_key?(:null)

        index_options = {}
        index_options[:name] = options.delete(:index) if options.has_key?(:index)

        returning belongs_to_without_field_declarations(name, options, &block) do
          refl = reflections[name.to_sym]
          fkey = refl.primary_key_name
          declare_field(fkey.to_sym, :integer, column_options)
          if refl.options[:polymorphic]
            declare_polymorphic_type_field(name, column_options)
            index(["#{name}_type", fkey], index_options) if index_options[:name]!=false
          else
            index(fkey, index_options) if index_options[:name]!=false
          end
        end
      end


      # Declares the "foo_type" field that accompanies the "foo_id"
      # field for a polyorphic belongs_to
      def declare_polymorphic_type_field(name, column_options)
        type_col = "#{name}_type"
        declare_field(type_col, :string, column_options)
        # FIXME: Before hobofields was extracted, this used to now do:
        # never_show(type_col)
        # That needs doing somewhere
      end


      # Declare a rich-type for any attribute (i.e. getter method). This
      # does not effect the attribute in any way - it just records the
      # metadata.
      def declare_attr_type(name, type, options={})
        klass = HoboFields.to_class(type)
        attr_types[name] = HoboFields.to_class(type)
        klass.respond_to?(:declared) ? klass.declared(self, name, options) : nil
      end


      # Declare named field with a type and an arbitrary set of
      # arguments. The arguments are forwarded to the #field_added
      # callback, allowing custom metadata to be added to field
      # declarations.
      def declare_field(name, type, *args)
        options = args.extract_options!
        try.field_added(name, type, args, options)
        add_formatting_for_field(name, type, args)
        add_validations_for_field(name, type, args)
        add_index_for_field(name, args, options)
        declare_attr_type(name, type, options) unless HoboFields.plain_type?(type)
        field_specs[name] = HoboFields::FieldSpec.new(self, name, type, options)
        attr_order << name unless attr_order.include?(name)
      end


      # Add field validations according to arguments in the
      # field declaration
      def add_validations_for_field(name, type, args)
        validates_presence_of   name if args.include?(:required)
        validates_uniqueness_of name, :allow_nil => !args.include?(:required) if :unique.in?(args)

        type_class = HoboFields.to_class(type)
        if type_class && type_class.public_method_defined?("validate")
          self.validate do |record|
            r = record.send(name)
            v = r ? r.validate : nil
            record.errors.add(name, v) if v.is_a?(String)
          end
        end
      end

      def add_formatting_for_field(name, type, args)
        type_class = HoboFields.to_class(type)
        if type_class && type_class.instance_methods.include?("format")
          self.before_validation do |record|
            val = record.send(name)
            record.send("#{name}=", val ? val.format : nil)
          end
        end
      end

      def add_index_for_field(name, args, options)
        to_name = options.delete(:index)
        return unless to_name
        index_opts = {}
        index_opts[:unique] = args.include?(:unique) || options.delete(:unique)
        # support :index => true declaration
        index_opts[:name] = to_name unless to_name == true
        index(name, index_opts)
      end


      # Extended version of the acts_as_list declaration that
      # automatically delcares the 'position' field
      def acts_as_list_with_field_declaration(options = {})
        declare_field(options.fetch(:column, "position"), :integer)
        acts_as_list_without_field_declaration(options)
      end


      # Returns the type (a class) for a given field or association. If
      # the association is a collection (has_many or habtm) return the
      # AssociationReflection instead
      def attr_type(name)
        if attr_types.nil? && self != self.name.constantize
          raise RuntimeError, "attr_types called on a stale class object (#{self.name}). Avoid storing persistent references to classes"
        end

        attr_types[name] or

          if (refl = reflections[name.to_sym])
            if (refl.macro == :has_one || refl.macro == :belongs_to) && !refl.options[:polymorphic]
              refl.klass
            else
              refl
            end
          end or

          (col = column(name.to_s) and HoboFields::PLAIN_TYPES[col.type] || col.klass)
      end


      # Return the entry from #columns for the named column
      def column(name)
        return unless table_exists?
        name = name.to_s
        columns.find {|c| c.name == name }
      end

    end

  end

end
