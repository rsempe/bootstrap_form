module BootstrapForm
  class FormBuilder < ActionView::Helpers::FormBuilder
    delegate :content_tag, to: :@template

    def initialize(object_name, object, template, options, proc)
      super
      if options.fetch(:help, '').to_sym == :block
        @help_tag = :p
        @help_css = 'help-block'
      else
        @help_tag = :span
        @help_css = 'help-inline'
      end

      @help_after = options.fetch(:help_position, '').to_sym == :after

      @languages = options.delete(:languages)
    end

    %w{text_field text_area password_field collection_select file_field date_select select}.each do |method_name|
      define_method(method_name) do |name, *args|
        options = args.extract_options!.symbolize_keys!

        options[:placeholder] = I18n.t("bridge.%s.%s.help.example" % [object.class.to_s.underscore, name.to_s]) if options[:placeholder] == true

        if options.delete(:no_bootstrap)
          name = "%s_%s" % [name.to_s, options.delete(:locale)] if options[:locale]

          super(name, options.except(:label, :help, :no_label, :required))
        else
          class_names = ["control-group"]

          class_names << :error if object.errors[name].any?
          class_names << :error if no_translated_errors(name, options[:locale])
          class_names << :error if name == :attachment and (object.errors["%s_file_name" % name].any? or object.errors["%s_content_type" % name].any?)

          class_names << :last if options.delete(:last)

          content_tag :div, class: class_names.join(" ") do
            (options.delete(:no_label).blank? ? require_label(name, options[:label], {class: 'control-label'}.merge(options.slice(:required))) : "").html_safe +
            content_tag(:div, class: 'controls') do
              help = display_error_or_help(name, options[:help])
              help = content_tag(@help_tag, class: @help_css) { help } if help

              args << options.except(:label, :help, :locale, :required)

              name = "%s_%s" % [name.to_s, options.delete(:locale)] if options[:locale].present?

              content = super(name, *args)

              content = content_for method_name, name, content, options

              if @help_after
                (content + help).html_safe
              else
                ((help || "") + content).html_safe
              end

            end
          end
        end
      end
    end

    def display_error_or_help name, help_message
      if object.errors[name].any?
        object.errors[name].join(', ')
      elsif object.errors["%s_file_name" % name].any?
        object.errors["%s_file_name" % name].join(', ')
      else
        case help_message
        when true
          I18n.t("bridge.%s.%s.help.example" % [object.class.to_s.underscore, name.to_s])
        else
          help_message
        end
      end
    end

    def content_for method_name, field, content, options = {}
      case method_name.to_sym
        when :file_field
          content_tag :div, file_field_render(method_name, field, content, options), :style => "margin-top: 10px"
        else
          content
      end
    end

    def image_file_field(field, options = {})
      file_field(field, options.merge({file_type: :media, paperclip_style: "thumbnail", with_link_helper: true}))
    end

    def file_field_render(method_name, field, content, options = {})
      has_uploaded_file = @object.send("#{field}?") && object.id

      if options[:with_link_helper] == true and has_uploaded_file
        options[:file_type] ||= :file

        case options[:file_type].to_sym
          when :file, :pdf
            filelink_html = @template.link_to @object.send("#{field}_file_name"), @object.send("#{field}").url,:target => :blank
            filename_html = content_tag(:i, nil, class: "icon-file") + filelink_html

          when :media
            url = options[:paperclip_style] ? @object.send(field).url(options[:paperclip_style]) : @object.send(field).url()

            filelink_html = options[:paperclip_style] ? @object.send(field).url(options[:paperclip_style]) : @object.send(field).url()
            filename_html = has_uploaded_file ? @template.image_tag(url, :class => options[:class]) : ""
        end

        remove_field  = hidden_field((options.delete(:use_remove_attribute) ? "remove_#{field}" : :"_destroy"))
        remove_link   = content_tag(:div, content_tag(:i, nil, class: "icon-remove") + I18n.t('bridge.form.remove_entry'), :onclick => "remove_attached_file(this)", :class => "remove_link")

        (filename_html + remove_field + remove_link + content).html_safe
      else
        content
      end
    end


    %w(i18n_text_field i18n_text_area).each do |method_name|
      define_method(method_name) do |name, *args|
        options = args.extract_options!.symbolize_keys!

        raise "Please defined :languages in bootstrap_form_for" if @languages.blank?

        options.merge!({tag_type: method_name.gsub("i18n_", "").to_sym})

        # When fields grouped
        if name.is_a?(Array)
          translation_fields name, options.merge!({no_label: true})
        else
          options.merge!({no_label: true, :last => true})

          translation_fields [name], options
        end
      end
    end

    def translation_fields names, options
      class_names = ["control-group"]
      class_names << :error if any_errors_on?(names)
      class_names << :last  if names.count != 1 and options.delete(:last).present?

      content_tag :div, class: class_names  do
        label_tag = if options.delete(:no_label).blank?
          require_label(options[:fields_grouped] ? options[:major_label] : names.first, options[:label], class: 'control-label')
        else
          ""
        end

        label_tag.html_safe +
        if @languages.length == 1
          language = default_language = @languages.first
          new_field = if options[:tag_type] == :file_field
            names.first
          else
            options[:fields_grouped] ? options[:major_label] : names.first
          end

          tabs_content = construct_tab_content(object, names, options[:fields_grouped] ? new_field : names.first, default_language == language.locale, language.locale, options)
        else
          html = if fields_translated?(object, names)
            construct_tabs(object, names, options)
          else
            raise "no field to translate"
          end

          if options.delete(:no_container) == true
            html
          else
            content_tag(:div, class: "tab-container") do
              content_tag(:span, "Translate", class: "translate-title") +
              content_tag(:div) do
                html
              end
            end
          end
        end
      end
    end

    def construct_tabs object, names, options = {}
      tabs_content     = []
      tabs             = []
      format           = language_tabs_format
      default_language = @languages.first.locale

      @languages.each do |language|
        tabs         << construct_tab(object, options[:fields_grouped] ? options[:major_label] : names.first, default_language, language, format, options)

        new_field = if options[:tag_type] == :file_field
          names.first
        else
          options[:fields_grouped] ? options[:major_label] : names.first
        end

        options[:locale] = language.locale
        tabs_content << construct_tab_content(object, names, options[:fields_grouped] ? new_field : names.first, default_language == language.locale, language.locale, options)
      end
      content_tag(:ul, tabs.join.html_safe          , class: "nav nav-tabs") +
      content_tag(:div, tabs_content.join.html_safe , class: "tab-content")
    end

    # datetime_picker : Display date and time picker
    # date_picker     : Display date picker
    # time_picker     : Display time picker
    %w(datetime_picker date_picker time_picker).each do |method_name|
      define_method(method_name) do |name, *args|
        options = args.extract_options!.symbolize_keys!.merge({:bypass_authorization => true})

        class_names = %w(control-group)
        class_names << :error if object.errors[name].any?

        content_tag :div, class: class_names do
          require_label(name, options.delete(:label), {class: 'control-label'}) +
          content_tag(:div, class: "controls form-inline") do
            case method_name
            when "datetime_picker"
              options.merge!({:bypass_authorization => true})

              text_field_for_date_picker((name.to_s + "_date").to_sym, options) +
              text_field_for_time_picker((name.to_s + "_time").to_sym, options)
            when "date_picker"
              text_field_for_date_picker(name, options)
            when "time_picker"
              text_field_for_time_picker(name, options)
            end
          end
        end

      end
    end


    def datetime_picker_from_to starts_at, ends_at, *args
      options = args.extract_options!.symbolize_keys!

      class_names = %w(control-group)
      class_names << :error if object.errors[starts_at].any? or object.errors[ends_at].any?

      content_tag :div, class: class_names do
        require_label(nil, options.delete(:major_label), {class: 'control-label'}.merge(options)) +
        content_tag(:div, class: "controls") do
          options.delete(:required)
          content_tag(:div, :class => "input-append input-prepend") do
            content_tag(:span) do
              text_field_for_date_time_picker(starts_at, options.merge({:label => I18n.t("date.from")}))
            end +
            content_tag(:i, nil, class: "icon-white") +
            content_tag(:span) do
              text_field_for_date_time_picker(ends_at, options.merge({:label => I18n.t("date.to")}))
            end
          end
        end
      end
    end


    def check_box(name, *args)
      options = args.extract_options!.symbolize_keys!

      class_names = ["control-group"]
      class_names << :error if object.errors[name].any?
      class_names << :last if options[:last]

      content_tag :div, class: class_names  do
        content_tag(:div, class: 'controls') do
          args << options.except(:label, :help)

          html = super(name, *args) + ' ' + (options[:label].blank? ? object.class.human_attribute_name(name) : options[:label])
          require_label(name, html, class: 'checkbox')
        end
      end
    end

    def actions(&block)
      content_tag :div, class: "form-actions" do
        block.call
      end
    end

    def primary(name, options = {})
      options.merge! class: 'btn btn-primary'

      submit name, options
    end

    def alert_message(title, *args)
      options = args.extract_options!
      css = options[:class] || "alert alert-error"

      if object.errors.full_messages.any?
        content_tag :div, class: css do
          title
        end
      end
    end


    private

    def construct_tab(object, field, default_language, language, format = :name, options = {})
      content_tag(:li, class: ('active' if language.locale == default_language)) do
        href = "#" << tab_id(object, field, language.locale, options)

        content_tag(:a,
          :"data-toggle" => :tab,
          :href          =>  href
        ) do
          @template.client_image_tag(:leadformance, "languages/png/%s.png" % language.locale, :class => :flag) +
          language[format].humanize
        end
      end
    end

    def construct_tab_content(object, methods, field, active = false, locale = :fr, options = {})
      html = []

      tab_pane_for(object, field, locale, active, options) do
        methods.each_with_index do |method, index|

          options[:label] = object.class.human_attribute_name(method)

          # options[:help] = I18n.t("bridge.%s.%s.help.example" % [object.class.to_s.underscore, method.to_s]) if options[:help] == true
          # raise options.inspect

          html << case options[:tag_type]
            when :text_field
              text_field(method, options.except(:tag_type).merge({:bypass_authorization => true}))
            when :text_area
              text_area(method, options.except(:tag_type).merge({:bypass_authorization => true}))
            when :file_field
              fields_for options[:object] do |attachment_fields|
                if attachment_fields.object.locale == locale
                  attachment_fields.hidden_field(:event_id) +
                  attachment_fields.hidden_field(:locale) +
                  attachment_fields.file_field(method, options.except(:tag_type))
                end
              end
          end
        end

        html.join().html_safe
      end
    end

    def tab_id(object, field, locale, options)
      # If file field, exception for generate id
      id = case options[:tag_type]
        when :file_field
          "%s_%s" % [options[:object], locale]
        else
          id = ""
          id << ("%s_" % options[:sub_field]) if options[:sub_field].present?

          id << "%s_%s_%s" % [field, locale, object.id]
      end

    end

    def tab_pane_for(object, field, locale, active = false, options, &block)
      id = tab_id(object, field, locale, options)

      content_tag(:div,
      :id    => id,
      :class => "tab-pane #{'active' if active}") do
        yield
      end
    end

    def language_tabs_format
      @languages.length > 4 ? :locale : :name
    end

    def text_field_for_date_time_picker name, options = {}
      content_tag(:span, (options.delete(:label) || object.class.human_attribute_name(name)) + mark_required(name), class: 'add-on').html_safe +
      text_field_for_date_picker(name.to_s + "_date", options.merge({:content_tag => :span})) +
      text_field(name.to_s + "_time", {:class => "bootstrap_date_time_picker input-mini", :no_bootstrap => true}.merge(options))
    end


    def text_field_for_date_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag(options[:content_tag] || :div, :class => "input-append input-prepend date bootstrap_date_picker", :"data-date" => object.send(name), :"data-date-format" => "dd/mm/yyyy") do
        text_field(name, {:class => "input-small", :no_bootstrap => true}.merge(options)) +
        content_tag(:span, class: "add-on") do
          content_tag(:i, nil, class: "icon-calendar")
        end
      end
    end

    def text_field_for_time_picker name, *args
      options = args.extract_options!.symbolize_keys!

      text_field(name, {:class => "bootstrap_date_time_picker", :no_bootstrap => true}.merge(options))
    end

    def fields_translated? object, fields
      object.class.respond_to?(:translates?) && object.class.translates? && [fields].flatten.map{|field| object.translated_attribute_names.include?(field.to_sym)}.index(false).blank?
    end

    def any_errors_on? fields
      fields.map{|name| object.errors[name].any?}.index(true).present?
    end

    def no_translated_errors(name, locale)
      locale.present? and !object.errors.select{|key, values| key.match(/^#{name}_[a-z]{2}$/) and values.present?}.keys.count.zero?
    end

    def require_label method, label = nil, *args
      options        = args.extract_options!.symbolize_keys!
      required_field = options.delete(:required)

      label(method, label, options).gsub("</label>", "%s</label>" % mark_required(method, required_field)).html_safe
    end

    def mark_required(attribute, bypass_required = false)
      return "*" if bypass_required == true
      return "" if bypass_required == false or attribute.blank?

      object.class.validators_on(attribute).map(&:class).include?(ActiveModel::Validations::PresenceValidator) ? "*" : ""
    end

  end
end
