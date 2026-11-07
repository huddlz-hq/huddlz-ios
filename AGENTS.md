## Git and PR attribution

- Never add AI, Codex, or OpenAI attribution to commit messages.
- Never add `Co-Authored-By` trailers for Codex.
- Never add generated-by attribution to pull request titles or descriptions.

## Communication

Use Zinsser’s four principles in all writing and responses, including documentation, code comments, commit messages, issues, and pull requests:

- **Clarity:** Say what you mean. Make the main point easy to find.
- **Simplicity:** Use plain words and direct sentences. Explain necessary jargon.
- **Brevity:** Cut repetition and words that add no meaning. Keep the details the reader needs.
- **Humanity:** Write like a thoughtful colleague. Be warm, honest, and natural.

## Behavior testing

- Our testing seams are behaviors people can observe: “clearing a search restores results” or “retrying a failed request shows cards.” Agree on these behaviors with the user. That agreement is enough; choose where to place the tests without asking again.
- Build one behavior at a time: write a failing test, make it pass, then move to the next behavior. When covering existing code, check that the test catches a broken version of the behavior.
- Use Apple’s native tools. Name tests after the behavior they verify.
- Put most behavior tests in Swift Testing at the store edge. Build the real store (such as `DiscoveryStore` or `AccountStore`) with its real client, and fake only the network with `HTTPFixture` responses. Drive the test through what a person does (search, load more, retry, sign in) and check the store state they would see. Don't mock the app’s own types or test private helpers, so a refactor that keeps behavior keeps its tests passing. Errors, retries, filters, pagination, cancellation, and races belong here.
- Keep XCUITest for the core journeys and their wiring: signing up, signing in, discovering, RSVPing, deleting an account, and system handoffs only the running app can show, such as permission prompts, Maps, and native refresh. Don't repeat a rule in a UI test when a store test covers it.
- When a rule lives in view `@State` and only a UI test can reach it, move that state into the store or a small model it owns, then test it there.
- Stub only external service boundaries, such as HTTP, Apple Maps, and Core Location. Keep the app’s request building, decoding, logic, and views real. Use native simulation and real system permission prompts where available; inject service failures only when needed to exercise recovery reliably. Check results people can observe, not private methods or internal calls.
- Keep tests independent of live data. Check the real backend separately, and report those checks separately from behavior tests.
- Run focused tests as you work and the full suite before handoff. Passing launch checks does not mean a feature is tested.

## Agent skills

### Issue tracker

Use GitHub Issues for this repo. Before reading or updating tickets, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. Before triaging issues, read `docs/agents/triage-labels.md`.

### Domain docs

Use a single root `CONTEXT.md` and `docs/adr/`. Before exploring domain terms or decisions, read `docs/agents/domain.md`.
