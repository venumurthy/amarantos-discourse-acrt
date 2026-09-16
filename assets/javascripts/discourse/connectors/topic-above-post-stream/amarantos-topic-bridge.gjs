import Component from "@glimmer/component";

export default class AmarantosTopicBridge extends Component {
  get topic() {
    return this.args.outletArgs?.model || this.args.model;
  }

  get guide() {
    return this.topic?.amarantos_related_guide;
  }

  <template>
    {{#if this.guide}}
      <aside class="amarantos-related-guide">
        <strong>Related Amarantos Guide</strong>
        <a href={{this.guide.url}} target="_blank" rel="noopener noreferrer">
          {{this.guide.title}}
        </a>
      </aside>
    {{/if}}
    <nav class="amarantos-authority-links" aria-label="Amarantos resources">
      <a href="https://amarantos.org/what-is-past-life-regression/">Learn about PLRT</a>
      <a href="https://amarantos.org/is-past-life-regression-safe/">Safety</a>
      <a href="https://amarantos.org/evidence-based-plrt/">Evidence</a>
      <a href="https://amarantos.org/amarantos-certified-past-life-regression-therapists/">Certified therapists</a>
      <a href="https://amarantos.org/home/training/">Training</a>
      <a href="https://amarantos.org/about/">About Amarantos</a>
    </nav>
  </template>
}
