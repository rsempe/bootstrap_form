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

    end

    %w{text_field text_area password_field collection_select file_field date_select select}.each do |method_name|
      define_method(method_name) do |name, *args|

        options = args.extract_options!.symbolize_keys!

        if options[:no_bootstrap]
          super(name, options.except(:label, :help, :no_label, :no_bootstrap))
        else
          class_names = ["control-group"]
          class_names << :error if object.errors[name].any?
          class_names << :error if name == :attachment and object.errors["%s_file_name" % name].any?

          class_names << :last if options[:last]


          content_tag :div, class: class_names.join(" ") do
            (options[:no_label].blank? ? label(name, options[:label], class: 'control-label') : "").html_safe +
            content_tag(:div, class: 'controls') do
              help = display_error_or_help(name, options[:help])
              help = content_tag(@help_tag, class: @help_css) { help } if help
              args << options.except(:label, :help, :no_label, :no_bootstrap, :last)

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
        help_message
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

        raise "no :languages options defined" if options[:languages].blank?

        options.merge!({tag_type: method_name.gsub("i18n_", "").to_sym})

        # When fields grouped
        if name.is_a?(Array)
          options.merge!({fields_grouped: true})
          translation_fields name, options
        else
          options.merge!({no_label: true, no_bootstrap: true})

          translation_fields [name], options
        end
      end
    end

    def translation_fields names, options
      # Raise if no major label configured when fields grouped
      raise "no :major_label configured" if options[:fields_grouped] and options[:major_label].blank?

      content_tag :div, class: "control-group#{(' error' if any_errors_on?(names))}"  do
        label(options[:fields_grouped] ? options[:major_label] : names.first, options[:label], class: 'control-label') +
        content_tag(:div, class: "tab-container") do
          content_tag(:span, "Translate",class: "translate-title") +
          content_tag(:div) do
            if fields_translated?(object, names)
              construct_tabs(object, names, options)
            else
              raise "no field to translate"
            end
          end
        end
      end
    end

    def construct_tabs object, names, options = {}
      tabs_content     = []
      tabs             = []
      format           = language_tabs_format(options[:languages])
      default_language = options[:languages].first.locale

      options.delete(:languages).each do |language|
        new_field = if options[:tag_type] == :file_field
          names.first
        else
          "%s_%s" % [options[:fields_grouped] ? options[:major_label] : names.first, language.locale]
        end

        tabs         << construct_tab(object, new_field, default_language, language, format, options)
        tabs_content << construct_tab_content(object, names, options[:fields_grouped] ? new_field : names.first, default_language == language.locale, language.locale, options)
      end
      content_tag(:ul, tabs.join.html_safe          , class: "nav nav-tabs") +
      content_tag(:div, tabs_content.join.html_safe , class: "tab-content")
    end

    def datetime_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag :div, class: "control-group control-group-margin" do
        label(name, options[:label], class: 'control-label') +
        content_tag(:div, class: "controls form-inline") do
          text_field_for_date_picker((name.to_s + "_date").to_sym, options) +
          text_field_for_time_picker((name.to_s + "_time").to_sym, options)
        end
      end
    end

    def date_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag :div, class: "control-group control-group-margin" do
        label(name, options[:label], class: 'control-label') +
        content_tag(:div, class: "controls") do
          text_field_for_date_picker(name, options)
        end
      end
    end

    def time_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag :div, class: "control-group control-group-margin" do
        label(name, options[:label], class: 'control-label') +
        content_tag(:div, class: "controls") do
          text_field_for_time_picker(name, options)
        end
      end

    end


    def check_box(name, *args)
      options = args.extract_options!.symbolize_keys!
      content_tag :div, class: "control-group#{(' error' if object.errors[name].any?)}"  do
        content_tag(:div, class: 'controls') do
          args << options.except(:label, :help)

          html = super(name, *args) + ' ' + (options[:label].blank? ? object.class.human_attribute_name(name) : options[:label])
          label(name, html, class: 'checkbox')
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
        # If file field, exception for generate id
        href = if options[:tag_type] == :file_field
          "%s_%s" % [options[:object], object.send(options[:object]).select{|attachment| attachment.locale == language.locale}.first.locale]
        else
          options[:sub_field].present? ? "#%s_%s_%s" % [options[:sub_field], field, object.id] : "#%s_%s" % [field, object.id]
        end

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

          if options[:help] == true
            help_label = I18n.t("bridge.%s.%s.help.example" % [object.class.to_s.underscore, method.to_s])
          end

          method          = "%s_%s" % [method, locale] unless options[:tag_type] == :file_field

          html << case options[:tag_type]
            when :text_field
              text_field(method, options.except(:tag_type).merge({:help => help_label}))
            when :text_area
              text_area(method, options.except(:tag_type).merge({:help => help_label}))
            when :file_field
              fields_for options[:object] do |attachment_fields|
                if attachment_fields.object.locale == locale
                  attachment_fields.hidden_field(:event_id) +
                  attachment_fields.hidden_field(:locale) +
                  attachment_fields.file_field(method, options.except(:tag_type).merge({:help => help_label}))
                end
              end
          end
        end

        html.join().html_safe
      end
    end

    def tab_pane_for(object, field, locale, active = false, options, &block)
      id = if options[:tag_type] == :file_field
        "%s_%s" % [options[:object], locale]
      else
        options[:sub_field].present? ? "%s_%s_%s" % [options[:sub_field], field, object.id] : "%s_%s" % [field, object.id]
      end


      content_tag(:div,
      :id    => id,
      :class => "tab-pane #{'active' if active}") do
        yield
      end
    end

    def language_tabs_format(languages)
      languages.count > 4 ? :locale : :name
    end


    def text_field_for_date_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag(:div, :class => "input-append date bootstrap_date_picker", :"data-date" => object.send(name), :"data-date-format" => "dd/mm/yyyy") do
        text_field(name, {:class => "input-small", :size => 10, :no_bootstrap => true}.merge(options)) +
        content_tag(:span, class: "add-on") do
          content_tag(:i, nil, class: "icon-calendar")
        end
      end
    end

    def text_field_for_time_picker name, *args
      options = args.extract_options!.symbolize_keys!

      content_tag(:div, class: "input-append", style: "margin-left: 3px") do
        text_field(name, {:class => "time_picker", :size => 5, :no_bootstrap => true}.merge(options)) +
        content_tag(:span, class: "add-on") do
          content_tag(:i, nil, class: "icon-time")
        end
      end
    end

    def fields_translated? object, fields
      object.class.respond_to?(:translates?) && object.class.translates? && [fields].flatten.map{|field| object.translated_attribute_names.include?(field.to_sym)}.index(false).blank?
    end

    def any_errors_on? fields
      fields.map{|name| object.errors[name].any?}.index(true).present?
    end

  end
end
