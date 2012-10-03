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
    end

    %w{text_field text_area password_field collection_select file_field date_select select}.each do |method_name|
      define_method(method_name) do |name, *args|
        options = args.extract_options!.symbolize_keys!

        if options[:no_bootstrap]
          super(name, options.except(:label, :help, :no_label, :no_bootstrap))
        else
          content_tag :div, class: "control-group#{(' error' if object.errors[name].any?)}"  do
            (options[:no_label].blank? ? label(name, options[:label], class: 'control-label') : "").html_safe +
            content_tag(:div, class: 'controls') do
              help = object.errors[name].any? ? object.errors[name].join(', ') : options[:help]
              help = content_tag(@help_tag, class: @help_css) { help } if help
              args << options.except(:label, :help, :no_label, :no_bootstrap)
              super(name, *args) + help
            end
          end
        end
      end
    end


    %w(i18n_text_field i18n_text_area).each do |method_name|
      define_method(method_name) do |name, *args|
        options = args.extract_options!.symbolize_keys!
        options.merge!({tag_type: method_name.gsub("i18n_", "").to_sym, no_label: true, no_bootstrap: true})

        translation_field name, options
      end
    end

    def translation_field name, options = {}
      content_tag :div, class: "control-group#{(' error' if object.errors[name].any?)}"  do
        label(name, options[:label], class: 'control-label') +
        content_tag(:div, class: "tab-container") do
          content_tag(:span, "Translate",class: "translate-title") +
          content_tag(:div) do
            if object.class.respond_to?(:translates?) && object.class.translates? && object.translated_attribute_names.include?(name.to_sym)
              default_language = options[:languages].first.locale

              # For the field, construction of the input translated
              tabs_content = []
              tabs    = []
              format  = language_tabs_format(options[:languages])
              options.delete(:languages).each do |language|
                new_field = "%s_%s" % [name, language.locale]

                tabs          << construct_tab(object, new_field, default_language, language, format, options)
                tabs_content  << construct_tab_content(object, name, new_field, default_language == language.locale, options)
              end
              content_tag(:ul, tabs.join.html_safe          , class: "nav nav-tabs") +
              content_tag(:div, tabs_content.join.html_safe , class: "tab-content")
            else
              raise "no field to translate"
            end

          end
        end
      end

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
        content_tag(:a, "data-toggle" => :tab, href: options[:sub_field].present? ? "#%s_%s_%s" % [options[:sub_field], field, object.id] : "#%s_%s" % [field, object.id]) do
          language[format].humanize
        end
      end
    end

    def construct_tab_content(object, method, field, is_active = false, options = {})
      content_tag(:div,
      :id    => options[:sub_field].present? ? "%s_%s_%s" % [options[:sub_field], field, object.id] : "%s_%s" % [field, object.id],
      :class => "tab-pane #{'active' if is_active}") do
        case options[:tag_type]
          when :text_field
            text_field(field, options.except(:tag_type))
          when :text_area
            text_area(field, options.except(:tag_type))
        end

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

  end
end
