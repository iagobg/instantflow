# Concurrency and live UX

[Design index](index.md)

## Consistency contract

PostgreSQL is authoritative; LiveView is a projection; PubSub invalidates; Presence is advisory. Commands remain safe against stale and forged input.

Every socket, command, draft, cache key, presence/topic subscription, and receipt has an explicit organization scope. A URL or selected organization is never itself authorization. Switching organizations mounts a fresh view and removes old subscriptions/projections; another tab retains its own scope. Late events/responses from the previous organization cannot update the new screen. Organization suspension and membership revocation invalidate the affected context. Include organization in deduplication keys and validate scope on replay.

| Situation | Required behavior |
|---|---|
| Same-section saves | One wins; loser sees conflict with draft preserved |
| Different-section saves | Both may succeed if stage and permission remain valid |
| Competing transitions | Exactly one commits |
| Save versus transition | Serialize via ticket lock and revalidate reviewed sections |
| Budget contention | Lock shared account and prevent overspending |
| Duplicate/lost-response retry | Stable key prevents duplicate business effects |
| Delivery failure | Business commit remains; retry is visible |
| Disconnect/missed event | Refetch current state; no blind offline write replay |

## Revision protocol

Proposed: ticket state revision for stage/assignment-sensitive changes and independent section revisions. Saves supply both observed ticket and section revision.

Every mutation briefly locks the ticket. Section saves lock their section, validate revisions, and increment only section revision. Transitions lock required sections in stable order and increment ticket state revision. Compare section revisions displayed in the approval review so changed content cannot be approved unknowingly.

Use one global lock order across authorization, budget, ticket, and section rows. Discover needed IDs, lock in that order, then revalidate relationships. Exercise contention/deadlock handling. Never hold locks while people type or external calls run.

No silent force overwrite, automatic text merge, or blind stale-approval retry.

## UX

Authorized presence such as “Ana está editando Documentos” has heartbeat/expiry and does not block writes.

Keep unsaved drafts separate from saved projections. Remote updates refresh clean sections and mark dirty ones with “Esta solicitação foi atualizada”. Offer authorized comparison and “Revisar alterações” / “Reaplicar minhas alterações”. Reapplication is a new guarded command.

Drafts remain in memory by default. Losing permission clears protected drafts/content instead of retaining them in browser storage.

Immediately show pending feedback and prevent repeat submission. “Alteração salva” appears only after acknowledgement. Lost acknowledgement reconciles through receipts. Disconnect displays “Conexão interrompida. Reconectando…” and disables authoritative actions.

Keep focus and dirty forms stable. Avoid silently reordering an actively used row. Use text/icons and restrained accessible announcements. All dragging has keyboard alternatives. Errors explain next actions without hidden-data leaks.

## Refresh protocol

Subscribe before initial fetch, then process queued invalidations. Events carry minimal IDs/revisions; refetch authorized data and tolerate duplicate/out-of-order events. Reconcile on reconnect and a proposed 30-second periodic refresh.

Re-evaluate filters/pagination and remove newly unreadable rows. Totals come from authorized committed queries, not client arithmetic. Avoid full-board reload per keystroke.

## References

- [Ecto optimistic locking](https://hexdocs.pm/ecto/Ecto.Changeset.html#optimistic_lock/3)
- [PostgreSQL isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- [Phoenix Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html)

These support the proposed protocol; they do not automatically supply the entire application guarantee.
