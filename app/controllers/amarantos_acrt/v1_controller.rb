# frozen_string_literal: true

require "uri"

class AmarantosAcrt::V1Controller < ::ApplicationController
  requires_plugin AmarantosAcrt::PLUGIN_NAME
  before_action :ensure_admin
  before_action :ensure_feature_enabled

  SEO_ACTIONS = %w[
    editorial_candidates
    set_related_guide
    clear_related_guide
    configure_categories
  ].freeze

  def health
    badge = Badge.find_by(id: badge_id)
    group = certified_group
    certification_issues = []
    seo_issues = []
    warnings = []
    certification_issues << "badge_#{badge_id}_missing" if badge.blank?
    warnings << "group_#{group_name}_missing" if group.blank?
    certification_issues << "plr_cases_category_missing" if Category.find_by(id: plr_category_id).blank?
    seo_issues << "qa_category_missing" if Category.find_by(id: qa_category_id).blank?
    if SiteSetting.amarantos_schema_enabled && defined?(DiscourseSolved) && SiteSetting.solved_add_schema_markup != "never"
      seo_issues << "disable_discourse_solved_schema_to_prevent_duplicate_qa_graphs"
    end
    badge_user_ids = badge ? UserBadge.where(badge_id: badge.id).distinct.pluck(:user_id).sort : []
    group_user_ids = group ? group.group_users.pluck(:user_id).sort : []
    warnings << "badge_group_membership_mismatch" if group.present? && badge_user_ids != group_user_ids
    certification_ready = SiteSetting.amarantos_acrt_enabled && certification_issues.empty?
    seo_ready = SiteSetting.amarantos_seo_bridge_enabled && SiteSetting.amarantos_schema_enabled && seo_issues.empty?

    render json: {
      ready: certification_ready,
      certification_ready: certification_ready,
      seo_ready: seo_ready,
      enforcement_ready: certification_ready && warnings.empty?,
      plugin_version: "1.2.3",
      badge_id: badge_id,
      group_name: group_name,
      issues: (certification_issues + seo_issues).uniq,
      certification_issues: certification_issues,
      seo_issues: seo_issues,
      warnings: warnings,
      features: {
        certification: SiteSetting.amarantos_acrt_enabled,
        seo_bridge: SiteSetting.amarantos_seo_bridge_enabled,
        category_schema: SiteSetting.amarantos_schema_enabled,
      },
      badge_holder_count: badge_user_ids.length,
      group_member_count: group_user_ids.length,
      checked_at: Time.zone.now.iso8601,
    }
  end

  def certification_state
    cursor, limit = pagination
    group = certified_group
    legacy_group = find_group(SiteSetting.amarantos_acrt_legacy_group_name)
    badge_ids = UserBadge.where(badge_id: badge_id).select(:user_id)
    group_ids = group ? GroupUser.where(group_id: group.id).select(:user_id) : User.none.select(:id)
    legacy_group_ids = legacy_group ? GroupUser.where(group_id: legacy_group.id).select(:user_id) : User.none.select(:id)
    users =
      User
        .where(id: badge_ids)
        .or(User.where(id: group_ids))
        .or(User.where(id: legacy_group_ids))
        .where("users.id > ?", cursor)
        .order(:id)
        .limit(limit + 1)
        .includes(:user_profile)
        .to_a
    has_more = users.length > limit
    users = users.first(limit)

    render json: {
      complete: true,
      users: users.map { |user| certification_user_json(user, group, legacy_group) },
      next_cursor: has_more ? users.last.id : 0,
    }
  end

  def user_certification_state
    user = find_user!
    raise Discourse::InvalidAccess if excluded_user?(user)
    render json: {
      complete: true,
      user: certification_user_json(
        user,
        certified_group,
        find_group(SiteSetting.amarantos_acrt_legacy_group_name),
      ),
    }
  end

  def activity
    user = find_user!
    from, to = date_window
    likes =
      PostAction
        .joins(post: { topic: :category })
        .where(user_id: user.id, post_action_type_id: PostActionType.types[:like], deleted_at: nil)
        .where(created_at: from..to)
        .where(posts: { deleted_at: nil })
        .where(topics: { deleted_at: nil, category_id: plr_category_id, archetype: Archetype.default })
        .where(categories: { read_restricted: false })
        .pluck("topics.id", "topics.category_id", "topics.user_id")
    replies =
      Post
        .joins(topic: :category)
        .where(user_id: user.id, deleted_at: nil)
        .where("posts.post_number > 1")
        .where(created_at: from..to)
        .where(topics: { deleted_at: nil, category_id: plr_category_id, archetype: Archetype.default })
        .where(categories: { read_restricted: false })
        .pluck("topics.id", "topics.category_id", "topics.user_id")
    events = likes.map { |row| activity_event(row, "like") } + replies.map { |row| activity_event(row, "reply") }

    topics =
      Topic
        .joins(:category)
        .where(user_id: user.id, category_id: plr_category_id, deleted_at: nil, archetype: Archetype.default)
        .where(created_at: from..to)
        .where(categories: { read_restricted: false })
        .order(:created_at)
        .to_a
    topic_ids = topics.map(&:id)
    reply_counts =
      if topic_ids.empty?
        {}
      else
        Post
          .where(topic_id: topic_ids, deleted_at: nil)
          .where("post_number > 1 AND user_id <> ?", user.id)
          .group(:topic_id)
          .count
      end

    render json: {
      complete: true,
      engagement_events: events,
      public_case_topics: topics.map { |topic| public_case_json(topic, reply_counts[topic.id].to_i) },
      counts: {
        like_events: likes.length,
        reply_events: replies.length,
        distinct_engagement_topics: events.map { |event| event[:topic_id] }.uniq.length,
        public_case_topics: topics.length,
      },
      window: { from: from.iso8601, to: to.iso8601 },
    }
  end

  def set_certification
    user = mutable_user!
    badge = Badge.find_by(id: badge_id)
    group = certified_group
    raise Discourse::NotFound if badge.blank? || group.blank?

    BadgeGranter.grant(badge, user, granted_by: current_user)
    group.add(user)
    StaffActionLogger.new(current_user).log_custom(
      "amarantos_acrt_granted",
      user_id: user.id,
      subject: safe_reason,
    )
    render json: { success: true, user_id: user.id, badge_active: true, group_active: true }
  end

  def clear_certification
    user = find_user!
    badge = Badge.find_by(id: badge_id)
    UserBadge.where(user_id: user.id, badge_id: badge_id).find_each do |user_badge|
      BadgeGranter.revoke(user_badge, revoked_by: current_user)
    end
    certified_group&.remove(user)
    StaffActionLogger.new(current_user).log_custom(
      "amarantos_acrt_revoked",
      user_id: user.id,
      subject: safe_reason,
    )
    render json: { success: true, user_id: user.id, badge_active: false, group_active: false }
  end

  def migrate_group
    badge = Badge.find_by(id: badge_id)
    raise Discourse::NotFound if badge.blank?

    target = certified_group
    legacy = find_group(SiteSetting.amarantos_acrt_legacy_group_name)
    migration_export = {
      generated_at: Time.zone.now.iso8601,
      badge_id: badge.id,
      badge_holder_ids: UserBadge.where(badge_id: badge.id).distinct.order(:user_id).pluck(:user_id),
      legacy_group: legacy ? { id: legacy.id, name: legacy.name, member_ids: legacy.group_users.order(:user_id).pluck(:user_id) } : nil,
      target_group: target ? { id: target.id, name: target.name, member_ids: target.group_users.order(:user_id).pluck(:user_id) } : nil,
    }
    migration = "existing_target"
    if target.blank? && legacy.present?
      renamed = !legacy.automatic? && legacy.update(
        name: group_name,
        full_name: AmarantosAcrt::CREDENTIAL_NAME,
        title: AmarantosAcrt::CREDENTIAL_NAME,
      )
      if renamed
        target = legacy
        migration = "renamed_legacy_group"
      else
        legacy.reload
      end
    end
    if target.blank?
      target = Group.create!(name: group_name, full_name: AmarantosAcrt::CREDENTIAL_NAME, title: AmarantosAcrt::CREDENTIAL_NAME)
      migration = "created_target_group"
    end

    target.update!(full_name: AmarantosAcrt::CREDENTIAL_NAME, title: AmarantosAcrt::CREDENTIAL_NAME)
    badge.update!(
      name: AmarantosAcrt::CREDENTIAL_NAME,
      description: AmarantosAcrt::CREDENTIAL_DESCRIPTION,
      long_description: AmarantosAcrt::CREDENTIAL_DESCRIPTION,
    )
    authoritative_ids = UserBadge.where(badge_id: badge.id).distinct.pluck(:user_id)
    current_ids = target.group_users.pluck(:user_id)
    (authoritative_ids - current_ids).each do |user_id|
      user = User.find_by(id: user_id)
      target.add(user) if user.present?
    end
    (current_ids - authoritative_ids).each do |user_id|
      user = User.find_by(id: user_id)
      target.remove(user) if user.present?
    end
    verified = target.group_users.where(user_id: authoritative_ids).count == authoritative_ids.length &&
      target.group_users.where.not(user_id: authoritative_ids).none?
    legacy_retired = false
    if verified && legacy.present? && legacy.id != target.id
      legacy.group_users.includes(:user).find_each { |membership| legacy.remove(membership.user) }
      legacy.update!(
        full_name: "Retired — #{SiteSetting.amarantos_acrt_legacy_group_name}",
        title: nil,
        visibility_level: Group.visibility_levels[:staff],
        members_visibility_level: Group.visibility_levels[:staff],
      )
      legacy_retired = true
    end

    render json: {
      success: true,
      migration: migration,
      group_id: target.id,
      badge_id: badge.id,
      authoritative_member_count: authoritative_ids.length,
      verified: verified,
      legacy_group_retired: legacy_retired,
      migration_export: migration_export,
    }
  end

  def set_related_guide
    topic = public_topic!
    title = params[:title].to_s.strip.truncate(255)
    url = validated_guide_url(params[:url])
    raise Discourse::InvalidParameters.new(:title) if title.blank?

    topic.custom_fields[AmarantosAcrt::RELATED_GUIDE_FIELD] = { "title" => title, "url" => url }
    topic.save_custom_fields
    StaffActionLogger.new(current_user).log_custom(
      "amarantos_related_guide_set",
      topic_id: topic.id,
      subject: url,
    )
    render json: { success: true, topic_id: topic.id }
  end

  def clear_related_guide
    topic = Topic.find_by(id: params[:topic_id].to_i)
    raise Discourse::NotFound if topic.blank?
    topic.custom_fields.delete(AmarantosAcrt::RELATED_GUIDE_FIELD)
    topic.save_custom_fields
    render json: { success: true, topic_id: topic.id }
  end

  def dormancy_candidates
    cursor, limit = pagination(default_limit: 50, max_limit: 100)
    excluded = integration_user_ids + [Discourse::SYSTEM_USER_ID]
    cutoff = 365.days.ago
    users =
      User
        .where(active: true, admin: false, moderator: false, staged: false)
        .where.not(id: excluded)
        .where("users.id > ?", cursor)
        .where("COALESCE(users.last_seen_at, users.created_at) <= ?", cutoff)
        .order(:id)
        .limit(limit + 1)
        .to_a
    has_more = users.length > limit
    users = users.first(limit)
    now = Time.zone.now
    render json: {
      complete: true,
      users: users.map do |user|
        last_seen = user.last_seen_at || user.created_at
        {
          id: user.id,
          username: user.username,
          last_seen_at: last_seen&.iso8601,
          inactive_days: ((now - last_seen) / 1.day).floor,
          warned: user.custom_fields[AmarantosAcrt::DORMANCY_WARNED_FIELD].present?,
          warned_at: user.custom_fields[AmarantosAcrt::DORMANCY_WARNED_FIELD],
          suspended: user.suspended?,
          excluded: excluded_user?(user),
        }
      end,
      next_cursor: has_more ? users.last.id : 0,
    }
  end

  def dormancy
    user = mutable_user!
    action = params[:action].to_s
    case action
    when "warn"
      unless user.custom_fields[AmarantosAcrt::DORMANCY_WARNED_FIELD].present?
        PostCreator.create!(
          Discourse.system_user,
          archetype: Archetype.private_message,
          subtype: TopicSubtype.system_message,
          target_usernames: user.username,
          title: I18n.t("amarantos_acrt.dormancy_warning_title"),
          raw: I18n.t("amarantos_acrt.dormancy_warning_body"),
        )
        user.custom_fields[AmarantosAcrt::DORMANCY_WARNED_FIELD] = Time.zone.now.iso8601
        user.save_custom_fields
      end
    when "suspend"
      clear_certification_for(user)
      user.user_option.update!(
        mailing_list_mode: false,
        email_digests: false,
        email_level: UserOption.email_level_types[:never],
        email_messages_level: UserOption.email_level_types[:never],
      )
      unless user.suspended?
        UserSuspender.new(
          user,
          suspended_till: 100.years.from_now,
          reason: I18n.t("amarantos_acrt.dormancy_suspend_reason"),
          by_user: current_user,
        ).suspend
      end
    else
      raise Discourse::InvalidParameters.new(:action)
    end
    render json: { success: true, user_id: user.id, action: action }
  end

  def reactivate
    user = find_user!
    raise Discourse::InvalidAccess if excluded_user?(user)
    if user.suspended?
      user.update!(suspended_till: nil, suspended_at: nil)
      StaffActionLogger.new(current_user).log_user_unsuspend(user)
      DiscourseEvent.trigger(:user_unsuspended, user: user)
    end
    render json: {
      success: true,
      user_id: user.id,
      certification_restored: false,
      email_preferences_restored: false,
    }
  end

  def editorial_candidates
    limit = [[params.fetch(:limit, 50).to_i, 1].max, 50].min
    category_ids = setting_ids(SiteSetting.amarantos_acrt_editorial_category_ids)
    topics =
      Topic
        .joins(:category)
        .includes(:first_post, :tags)
        .where(category_id: category_ids, deleted_at: nil, archetype: Archetype.default, visible: true)
        .where(categories: { read_restricted: false })
        .where("topics.created_at >= ?", 180.days.ago)
        .order("topics.bumped_at DESC")
        .limit(200)
        .to_a
    ranked = topics.map { |topic| editorial_topic_json(topic) }.sort_by do |topic|
      -(topic[:relevance] + topic[:originality] + topic[:activity] + topic[:completeness])
    end.first(limit)
    render json: { complete: true, topics: ranked }
  end

  def configure_categories
    private_ids = setting_ids(SiteSetting.amarantos_acrt_member_only_category_ids)
    public_ids = setting_ids(SiteSetting.amarantos_acrt_public_category_ids)
    missing = []
    private_ids.each do |category_id|
      category = Category.find_by(id: category_id)
      if category.blank?
        missing << category_id
        next
      end
      permissions = preserved_category_permissions(category, except_group: "everyone")
      permissions["trust_level_0"] ||= :full
      category.set_permissions(permissions)
      category.save!
    end
    public_ids.each do |category_id|
      category = Category.find_by(id: category_id)
      if category.blank?
        missing << category_id
        next
      end
      permissions = preserved_category_permissions(category)
      permissions["everyone"] = :full
      category.set_permissions(permissions)
      category.save!
    end
    private_verified = Category.where(id: private_ids, read_restricted: true).count == private_ids.length
    public_verified = Category.where(id: public_ids, read_restricted: false).count == public_ids.length
    render json: {
      success: missing.empty? && private_verified && public_verified,
      private_category_ids: private_ids,
      public_category_ids: public_ids,
      missing_category_ids: missing,
      verified: missing.empty? && private_verified && public_verified,
    }
  end

  private

  def preserved_category_permissions(category, except_group: nil)
    category.category_groups.includes(:group).each_with_object({}) do |category_group, permissions|
      group_name = category_group.group&.name
      next if group_name.blank? || group_name == except_group

      permission = CategoryGroup.permission_types.key(category_group.permission_type)
      permissions[group_name] = permission.to_sym if permission.present?
    end
  end

  def ensure_feature_enabled
    return if action_name == "health"

    enabled = if SEO_ACTIONS.include?(action_name)
      SiteSetting.amarantos_seo_bridge_enabled
    else
      SiteSetting.amarantos_acrt_enabled
    end
    raise Discourse::NotFound unless enabled
  end

  def badge_id
    SiteSetting.amarantos_acrt_badge_id
  end

  def group_name
    SiteSetting.amarantos_acrt_group_name
  end

  def plr_category_id
    SiteSetting.amarantos_acrt_plr_cases_category_id
  end

  def qa_category_id
    SiteSetting.amarantos_acrt_qa_category_id
  end

  def find_group(name)
    Group.find_by("LOWER(name) = ?", name.to_s.downcase)
  end

  def certified_group
    find_group(group_name)
  end

  def find_user!
    User.find_by(id: params[:user_id].to_i).tap { |user| raise Discourse::NotFound if user.blank? }
  end

  def mutable_user!
    find_user!.tap { |user| raise Discourse::InvalidAccess if excluded_user?(user) }
  end

  def excluded_user?(user)
    user.blank? || user.staff? || user.staged? || user.id <= 0 || integration_user_ids.include?(user.id)
  end

  def integration_user_ids
    setting_ids(SiteSetting.amarantos_acrt_integration_user_ids)
  end

  def setting_ids(value)
    Array(value).flat_map { |item| item.to_s.split("|") }.map(&:to_i).select(&:positive?).uniq
  end

  def pagination(default_limit: 100, max_limit: 100)
    [
      [params.fetch(:cursor, 0).to_i, 0].max,
      [[params.fetch(:limit, default_limit).to_i, 1].max, max_limit].min,
    ]
  end

  def date_window
    raw_from = params.require(:from).to_s
    raw_to = params.require(:to).to_s
    from = Time.zone.parse(raw_from)
    to = Time.zone.parse(raw_to)
    to = to.end_of_day if raw_to.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    raise Discourse::InvalidParameters.new(:from) if from.blank? || to.blank? || from > to || from < 10.years.ago
    [from, to]
  rescue ArgumentError
    raise Discourse::InvalidParameters.new(:from)
  end

  def activity_event(row, action)
    {
      topic_id: row[0].to_i,
      category_id: row[1].to_i,
      topic_author_id: row[2].to_i,
      action: action,
      public: true,
      deleted: false,
    }
  end

  def public_case_json(topic, non_author_reply_count)
    {
      id: topic.id,
      category_id: topic.category_id,
      author_id: topic.user_id,
      title: topic.title,
      url: "#{Discourse.base_url}#{topic.relative_url}",
      created_at: topic.created_at.iso8601,
      non_author_reply_count: non_author_reply_count,
      public: true,
      deleted: false,
    }
  end

  def certification_user_json(user, group, legacy_group = nil)
    badge_active = UserBadge.exists?(user_id: user.id, badge_id: badge_id)
    group_active = group.present? && GroupUser.exists?(user_id: user.id, group_id: group.id)
    legacy_group_active = legacy_group.present? && GroupUser.exists?(user_id: user.id, group_id: legacy_group.id)
    {
      id: user.id,
      username: user.username,
      badge_active: badge_active,
      group_active: group_active,
      legacy_group_active: legacy_group_active,
      credential_active: badge_active || group_active || legacy_group_active,
      suspended: user.suspended?,
      last_seen_at: user.last_seen_at&.iso8601,
      profile: AmarantosAcrt::PublicProfilePayload.for(user, plr_category_id),
    }
  end

  def safe_reason
    params[:reason].to_s.strip.truncate(180)
  end

  def public_topic!
    topic = Topic.joins(:category).find_by(id: params[:topic_id].to_i, deleted_at: nil, archetype: Archetype.default)
    raise Discourse::NotFound if topic.blank? || topic.category.read_restricted?
    topic
  end

  def validated_guide_url(raw)
    uri = URI.parse(raw.to_s)
    valid_hosts = %w[amarantos.org www.amarantos.org]
    raise Discourse::InvalidParameters.new(:url) unless uri.scheme == "https" &&
      valid_hosts.include?(uri.host&.downcase) &&
      uri.userinfo.blank? &&
      [nil, 443].include?(uri.port)
    uri.to_s
  rescue URI::InvalidURIError
    raise Discourse::InvalidParameters.new(:url)
  end

  def clear_certification_for(user)
    UserBadge.where(user_id: user.id, badge_id: badge_id).find_each do |user_badge|
      BadgeGranter.revoke(user_badge, revoked_by: current_user)
    end
    certified_group&.remove(user)
  end

  def editorial_topic_json(topic)
    first_post = topic.first_post
    excerpt = first_post ? ActionController::Base.helpers.strip_tags(PrettyText.excerpt(first_post.cooked, 360)) : ""
    word_count = first_post&.raw.to_s.split.length
    relevance = topic.category_id == plr_category_id ? 100 : 70
    originality = [[word_count / 4, 100].min, 20].max
    activity = [[topic.posts_count * 8 + topic.like_count * 5, 100].min, 10].max
    completeness = [[word_count / 3 + topic.reply_count * 10, 100].min, 10].max
    {
      id: topic.id,
      category_id: topic.category_id,
      title: topic.title,
      url: "#{Discourse.base_url}#{topic.relative_url}",
      excerpt: excerpt,
      tags: topic.tags.map(&:name),
      relevance: relevance,
      originality: originality,
      activity: activity,
      completeness: completeness,
      public: true,
      deleted: false,
    }
  end
end
