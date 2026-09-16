# frozen_string_literal: true

module ::AmarantosAcrt
  module PublicProfilePayload
    FIELD_SETTINGS = {
      city: :amarantos_acrt_profile_city_field_id,
      state: :amarantos_acrt_profile_state_field_id,
      country: :amarantos_acrt_profile_country_field_id,
      languages: :amarantos_acrt_profile_languages_field_id,
      professional_role: :amarantos_acrt_profile_role_field_id,
      batch: :amarantos_acrt_profile_batch_field_id,
      certificate_issued_at: :amarantos_acrt_profile_issue_date_field_id,
      certificate_expires_at: :amarantos_acrt_profile_expiry_date_field_id,
    }.freeze

    def self.for(user, plr_category_id)
      values = UserCustomField.where(user_id: user.id).pluck(:name, :value).to_h
      fields = FIELD_SETTINGS.to_h do |output_key, setting|
        field_id = SiteSetting.public_send(setting).to_i
        [output_key, field_id.positive? ? values["user_field_#{field_id}"].to_s : ""]
      end
      cases =
        Topic
          .joins(:category)
          .where(user_id: user.id, category_id: plr_category_id, deleted_at: nil, archetype: Archetype.default)
          .where(categories: { read_restricted: false })
          .order(created_at: :desc)
          .limit(6)
          .map { |topic| { id: topic.id, title: topic.title, url: "#{Discourse.base_url}#{topic.relative_url}" } }
      {
        name: user.name.presence || user.username,
        photo_url: absolute_avatar_url(user),
        city: fields[:city],
        state: fields[:state],
        country: fields[:country],
        languages: fields[:languages].split(/[,|]/).map(&:strip).reject(&:blank?).first(12),
        professional_role: fields[:professional_role],
        biography: safe_biography(user.user_profile&.bio_raw.to_s),
        batch: fields[:batch],
        certificate_issued_at: fields[:certificate_issued_at],
        certificate_expires_at: fields[:certificate_expires_at],
        selected_cases: cases,
        forum_profile_url: "#{Discourse.base_url}/u/#{UrlHelper.encode_component(user.username)}",
      }
    end

    def self.absolute_avatar_url(user)
      path = user.avatar_template.to_s.gsub("{size}", "288")
      path.start_with?("http://", "https://") ? path : "#{Discourse.base_url}#{path}"
    end

    def self.safe_biography(value)
      value
        .to_s
        .gsub(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i, "")
        .gsub(%r{(?:https?://|www\.)\S+}i, "")
        .gsub(/(?<!\w)\+?\d[\d\s().\-]{7,}\d(?!\w)/, "")
        .strip
    end
  end
end
