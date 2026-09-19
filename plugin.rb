# frozen_string_literal: true

# name: amarantos-acrt
# about: Connects public PLRT forum activity, ACRT badge proof, guide mappings and safe dormancy controls to Amarantos.
# version: 1.2.5
# authors: Amarantos
# url: https://amarantos.org/
# required_version: 3.3.0

enabled_site_setting :amarantos_synergy_enabled

register_asset "stylesheets/amarantos-acrt.scss"

module ::AmarantosAcrt
  PLUGIN_NAME = "amarantos-acrt"
  RELATED_GUIDE_FIELD = "amarantos_related_guide"
  DORMANCY_WARNED_FIELD = "amarantos_dormancy_warned_at"
  CREDENTIAL_NAME = "Amarantos® Certified Regression Therapist"
  CREDENTIAL_DESCRIPTION =
    "Professionally certified in Clinical Hypnotherapy, PLRT, FLP, LBL, EMDR, Perinatal Regression and InterGen Trauma Release"
end

require_relative "lib/amarantos_acrt/engine"
require_relative "lib/amarantos_acrt/public_profile"
require_relative "lib/amarantos_acrt/public_profile_payload"

after_initialize do
  register_topic_custom_field_type(AmarantosAcrt::RELATED_GUIDE_FIELD, :json)
  register_user_custom_field_type(AmarantosAcrt::DORMANCY_WARNED_FIELD, :string)

  add_to_serializer(:topic_view, :amarantos_related_guide) do
    object.topic.custom_fields[AmarantosAcrt::RELATED_GUIDE_FIELD]
  end

  add_to_serializer(
    :topic_view,
    :include_amarantos_related_guide?,
  ) { object.topic.custom_fields[AmarantosAcrt::RELATED_GUIDE_FIELD].present? }

  add_api_key_scope(
    :amarantos_acrt,
    read: {
      actions: %w[
        amarantos_acrt/v1#health
        amarantos_acrt/v1#certification_state
        amarantos_acrt/v1#user_certification_state
        amarantos_acrt/v1#activity
        amarantos_acrt/v1#dormancy_candidates
        amarantos_acrt/v1#editorial_candidates
      ],
    },
    write: {
      actions: %w[
        amarantos_acrt/v1#set_certification
        amarantos_acrt/v1#clear_certification
        amarantos_acrt/v1#migrate_group
        amarantos_acrt/v1#set_related_guide
        amarantos_acrt/v1#clear_related_guide
        amarantos_acrt/v1#dormancy
        amarantos_acrt/v1#reactivate
        amarantos_acrt/v1#configure_categories
      ],
    },
  )

  register_html_builder("server:topic-show-after-posts-crawler") do |controller|
    AmarantosAcrt::PublicProfile.topic_footer_html(controller)
  end

  register_modifier(:topic_crawler_container_schema) do |schema, topic|
    if SiteSetting.amarantos_schema_enabled && topic.category_id == SiteSetting.amarantos_acrt_qa_category_id
      { itemscope: true, itemtype: "https://schema.org/QAPage" }
    else
      schema
    end
  end

  register_modifier(:topic_crawler_main_entity_schema) do |schema, topic|
    if SiteSetting.amarantos_schema_enabled && topic.category_id == SiteSetting.amarantos_acrt_qa_category_id
      { itemprop: "mainEntity", itemscope: true, itemtype: "https://schema.org/Question" }
    else
      schema
    end
  end

  register_modifier(:topic_crawler_post_schema) do |schema, post, topic|
    if SiteSetting.amarantos_schema_enabled && topic.category_id == SiteSetting.amarantos_acrt_qa_category_id
      if post.is_first_post?
        { itemprop: "text" }
      else
        { itemprop: "suggestedAnswer", itemscope: true, itemtype: "https://schema.org/Answer" }
      end
    else
      schema
    end
  end
end
