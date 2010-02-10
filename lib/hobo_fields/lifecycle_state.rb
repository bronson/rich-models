module HoboFields
  class LifecycleState < String

    COLUMN_TYPE = :string
    HoboFields.register_type(:lifecycle_state, self)

    class << self
      attr_accessor :table_name
    end

    def to_html(xmldoctype = true)
      I18n.t("#{self.class.table_name}.states.#{self}", :default => self)
    end
  end
end
