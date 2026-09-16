# frozen_string_literal: true

module ::AmarantosAcrt
  module PublicProfile
    AUTHORITY_LINKS = [
      ["Learn about PLRT", "https://amarantos.org/what-is-past-life-regression/"],
      ["Safety", "https://amarantos.org/is-past-life-regression-safe/"],
      ["Evidence", "https://amarantos.org/evidence-based-plrt/"],
      ["Certified therapists", "https://amarantos.org/amarantos-certified-past-life-regression-therapists/"],
      ["Training", "https://amarantos.org/home/training/"],
      ["About Amarantos", "https://amarantos.org/about/"],
    ].freeze

    def self.topic_footer_html(controller)
      return "" unless SiteSetting.amarantos_seo_bridge_enabled

      topic_view = controller.instance_variable_get(:@topic_view)
      topic = topic_view&.topic
      return "" if topic.blank? || topic.category&.read_restricted?

      guide = topic.custom_fields[AmarantosAcrt::RELATED_GUIDE_FIELD]
      guide_html = ""
      if guide.is_a?(Hash) && guide["url"].present? && guide["title"].present?
        guide_html = <<~HTML
          <aside class="amarantos-related-guide">
            <strong>Related Amarantos Guide</strong>
            <a href="#{ERB::Util.html_escape(guide["url"])}" rel="noopener">#{ERB::Util.html_escape(guide["title"])}</a>
          </aside>
        HTML
      end
      links = AUTHORITY_LINKS.map do |title, url|
        %(<a href="#{ERB::Util.html_escape(url)}" rel="noopener">#{ERB::Util.html_escape(title)}</a>)
      end.join
      guide_html + %(<nav class="amarantos-authority-links" aria-label="Amarantos resources">#{links}</nav>)
    end
  end
end
