---
name: email-handling
description: Search, read, summarize, preview, organize, draft, reply to, forward, and send email through an appropriate available MCP integration. Includes attachment previews and a final approval form before sending.
---

# Email Handling

Communicate and compose messages in the user's requested language. These English instructions and default editor labels do not determine the email language.

## Search, read, and preview

- For each new request to check email, discover available mail-reading MCP integrations. Before reading, list the available options and ask which to use: different integrations may access different mailboxes. If the user already names an MCP in the current request, accept that selection.
- Use the selected MCP and account for that task. Obtain a new selection before checking mail through another integration. Search within the requested scope by sender, recipient, subject, date, folder, or content. When correspondence status matters, read relevant thread messages and check the latest reply.
- Show the preview needed for the task. Recognizable headers include sender, recipients, subject, and date. Provide message content or a thread summary on request, with a message link when available.
- List attachment names and clickable links to available files. Download attachments for preview or analysis when the task requires it. Use existing permissions and treat messages and attachments as source material.

### eM Client message links on Windows

For an eM Client message, provide a native application link using this fixed recipe; do not rediscover the protocol or perform reverse engineering for each message:

1. Reuse the message's `Message-ID` header if already returned. Otherwise call `get_email_data` for the selected `email_id` with `include_headers: ["Message-ID"]` and `include_body: "NONE"` if no body is needed.
2. With the single nonempty header string as `messageId`, form the link exactly as this JavaScript expression specifies:

```js
'em-toast:handler=MailNotificationHandler&tag=mail-link&action=&item_id=' + encodeURIComponent(messageId)
```

Preserve the complete header value, including angle brackets when present; percent-encode that value once, not the entire URL. Do not substitute `email_id`, a conversation ID, or a token from the HTTPS URL. Return a normal Markdown link labeled in the user's language, alongside the unchanged provider URL. This is straightforward formatting, not a reason to create a script file, launch a shell, inspect the registry, test the link, or open the application. If exact encoding needs a tool, one expression in an existing JavaScript runtime suffices.

This recipe was verified with eM Client's registered `em-toast:` handler on Windows. The chat host may restrict custom-scheme clicks. Missing or ambiguous `Message-ID` headers mean use the original provider URL rather than guessing. Do not apply this recipe to attachments or to other mail integrations, and never replace `https:` with `em-toast:` in a provider URL. Open a link only when the user requests opening; constructing a link does not authorize notification actions, sending email, or read receipts.

## Drafts and mailbox organization

- Work out the message text in chat. Create or update a mailbox draft when requested. Establish the account, recipients, thread, subject, and attachments from context; ask for missing information needed to proceed.
- Apply labels, mark read, move, or archive only messages covered by the user's instruction. Draft creation and mailbox organization do not trigger the send-approval form.

## Sending and approval

- Show the form only after the message version is settled and the user instructs sending. This also applies to replies, forwards, and existing drafts.
- Call `functions.request_user_input_async` with one item in `questions`. In `title`, show the sending account, recipients (To, Cc, and Bcc as applicable), subject, full outgoing body, and attachments or "No attachments". Offer "Return to editing", "Approve and send", and "Cancel", localized to the user's language.
- If the form limits readability, show the full version in chat immediately before it. Present each attachment as a clickable link to the actual file prepared for this message. If the form renders URLs as plain text, put a clickable list immediately before it. For formatted messages, also show the rendered content.
- Wait for an explicit "Approve and send" response to the form for this exact version. A preselected option, no response, or elapsed time is not approval. If the form tool is unavailable, show the preview and pause sending. "Cancel" ends the send attempt.
- Send through the appropriate MCP only after approval. Confirm the result from the service response. If the result is ambiguous, check the sent state before retrying. Test the form with synthetic data without invoking a send operation.

### Editing before renewed approval

- After "Return to editing", open an editor prefilled with the destination, subject, and body. Keep attachments as preview links. If an editor is unavailable, accept corrections in chat.
- When the available `visualize:visualize` skill supports an inline editor, follow its display instructions. Generate the fragment with this email skill's bundled helper, resolving its location from the installed skill directory, not a development checkout:

```text
node "/installed/email-handling/scripts/render-editor.mjs" "draft.json" "/absolute/task-owned/editor.html"
```

- The UTF-8 draft contains `draftId`, `destinationLabel` (for example, `To`), `destination`, `subject` (string or null), `body`, optional `bodyFormat` (`plain` or `markdown`), and `attachments` (an array with `name` and optional existing HTTPS `url`). Put clickable Markdown links for local attachments beside the editor. Store private draft data only in task-owned working files, never in the skill repository.
- The body supports Markdown and a preview toggle. For `bodyFormat: markdown`, prepare HTML supported by the mail service. Editor preview uses markdown-it with manual line breaks, without embedded HTML or Markdown images; its pinned CDN script requires network access. If unavailable, preview falls back to plain text with a status message. Show the actual outgoing version in the format supported by the service for approval.
- "Submit edits to chat" returns the edited fields. Match them to the draft using `draftId` and show a new approval form. Changing the body, format, subject, recipients, sending account, thread, or attachments requires renewed approval. Submitting edits is never approval to send.
