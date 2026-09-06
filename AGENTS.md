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
- Use Apple’s native tools. Use XCTest/XCUITest to tap through the app and check what appears. Use Swift Testing through public interfaces for behaviors such as cancellation, pagination, and overlapping searches. Name tests after the behavior they verify.
- Stub only the external HTTP service. Keep the app’s request building, decoding, logic, and views real wherever the test exercises them. Check results people can observe, not private methods or internal calls.
- Keep tests independent of live data. Check the real backend separately, and report those checks separately from behavior tests.
- Run focused tests as you work and the full suite before handoff. Passing launch checks does not mean a feature is tested.
