# frozen_string_literal: true

RSpec.describe AmarantosAcrt::V1Controller do
  fab!(:admin)
  fab!(:user)
  fab!(:badge) { Fabricate(:badge, id: 103) }
  fab!(:group) { Fabricate(:group, name: "ACRT") }
  fab!(:plr_category) { Fabricate(:category, id: 10) }

  before do
    SiteSetting.amarantos_synergy_enabled = true
    SiteSetting.amarantos_acrt_enabled = true
    SiteSetting.amarantos_seo_bridge_enabled = false
    SiteSetting.amarantos_schema_enabled = false
    SiteSetting.amarantos_acrt_badge_id = badge.id
    SiteSetting.amarantos_acrt_group_name = group.name
    SiteSetting.amarantos_acrt_plr_cases_category_id = plr_category.id
  end

  it "rejects unauthenticated service calls" do
    get "/amarantos-acrt/v1/certification-state.json"
    expect(response.status).to eq(403)

    get "/amarantos-acrt/v1/users/#{user.id}/certification-state.json"
    expect(response.status).to eq(403)
  end

  it "returns badge and group proof without private contact data" do
    sign_in(admin)
    BadgeGranter.grant(badge, user, granted_by: admin)
    group.add(user)

    get "/amarantos-acrt/v1/certification-state.json"
    expect(response.status).to eq(200)
    payload = response.parsed_body["users"].first
    expect(payload.slice("id", "badge_active", "group_active")).to eq(
      "id" => user.id,
      "badge_active" => true,
      "group_active" => true,
    )
    expect(payload.to_json).not_to include(user.email)
  end

  it "returns only the requested user's certification state" do
    sign_in(admin)
    other_user = Fabricate(:user)
    BadgeGranter.grant(badge, user, granted_by: admin)
    group.add(user)

    get "/amarantos-acrt/v1/users/#{user.id}/certification-state.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["complete"]).to eq(true)
    expect(response.parsed_body["user"].slice("id", "badge_active", "group_active")).to eq(
      "id" => user.id,
      "badge_active" => true,
      "group_active" => true,
    )
    expect(response.parsed_body.to_json).not_to include(user.email, other_user.email)
  end

  it "returns an unbadged linked user" do
    sign_in(admin)

    get "/amarantos-acrt/v1/users/#{user.id}/certification-state.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["user"]["id"]).to eq(user.id)
    expect(response.parsed_body["user"]["badge_active"]).to eq(false)
    expect(response.parsed_body["user"]["credential_active"]).to eq(false)
  end

  it "rejects a missing certification-state user" do
    sign_in(admin)

    get "/amarantos-acrt/v1/users/99999999/certification-state.json"

    expect(response.status).to eq(404)
  end

  it "does not expose staff certification state" do
    sign_in(admin)

    get "/amarantos-acrt/v1/users/#{admin.id}/certification-state.json"

    expect(response.status).to eq(403)
  end

  it "does not count engagement in a member-only category" do
    sign_in(admin)
    plr_category.set_permissions(trust_level_0: :full)
    plr_category.save!
    topic = Fabricate(:topic, category: plr_category)
    post = Fabricate(:post, topic: topic)
    PostActionCreator.like(user, post)

    get "/amarantos-acrt/v1/users/#{user.id}/activity.json", params: { from: 1.day.ago.to_date, to: Date.current }
    expect(response.status).to eq(200)
    expect(response.parsed_body["engagement_events"]).to be_empty
  end

  it "grants and revokes badge 103 and ACRT membership together" do
    sign_in(admin)

    post "/amarantos-acrt/v1/users/#{user.id}/certification.json", params: { reason: "labelled test" }
    expect(response.status).to eq(200)
    expect(UserBadge.exists?(user_id: user.id, badge_id: badge.id)).to eq(true)
    expect(GroupUser.exists?(user_id: user.id, group_id: group.id)).to eq(true)

    delete "/amarantos-acrt/v1/users/#{user.id}/certification.json", params: { reason: "labelled test" }
    expect(response.status).to eq(200)
    expect(UserBadge.exists?(user_id: user.id, badge_id: badge.id)).to eq(false)
    expect(GroupUser.exists?(user_id: user.id, group_id: group.id)).to eq(false)
  end

  it "refuses dormancy actions against staff" do
    sign_in(admin)
    post "/amarantos-acrt/v1/users/#{admin.id}/dormancy.json", params: { action: "suspend" }
    expect(response.status).to eq(403)
    expect(admin.reload.suspended?).to eq(false)
  end

  it "keeps certification routes disabled while SEO features are enabled" do
    sign_in(admin)
    SiteSetting.amarantos_acrt_enabled = false
    SiteSetting.amarantos_seo_bridge_enabled = true

    get "/amarantos-acrt/v1/certification-state.json"
    expect(response.status).to eq(404)

    get "/amarantos-acrt/v1/users/#{user.id}/certification-state.json"
    expect(response.status).to eq(404)

    get "/amarantos-acrt/v1/editorial-candidates.json"
    expect(response.status).to eq(200)
  end

  it "preserves existing group permissions when making categories member-only" do
    sign_in(admin)
    SiteSetting.amarantos_seo_bridge_enabled = true
    private_category = Fabricate(:category)
    public_category = Fabricate(:category)
    specialist_group = Fabricate(:group, name: "ATT-test")
    private_category.set_permissions(
      "everyone" => :readonly,
      "trust_level_0" => :create_post,
      specialist_group.name => :full,
    )
    private_category.save!
    SiteSetting.amarantos_acrt_member_only_category_ids = private_category.id.to_s
    SiteSetting.amarantos_acrt_public_category_ids = public_category.id.to_s

    post "/amarantos-acrt/v1/configure-categories.json"

    expect(response.status).to eq(200)
    expect(private_category.reload.read_restricted).to eq(true)
    expect(private_category.category_groups.exists?(group_id: Group::AUTO_GROUPS[:everyone])).to eq(false)
    expect(
      private_category.category_groups.exists?(
        group_id: specialist_group.id,
        permission_type: CategoryGroup.permission_types[:full],
      ),
    ).to eq(true)
    expect(
      private_category.category_groups.exists?(
        group_id: Group::AUTO_GROUPS[:trust_level_0],
        permission_type: CategoryGroup.permission_types[:create_post],
      ),
    ).to eq(true)
  end
end
