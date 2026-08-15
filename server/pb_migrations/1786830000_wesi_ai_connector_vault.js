migrate(
  (app) => {
    let existing = null;
    try { existing = app.findCollectionByNameOrId("wesi_ai_connector_vault"); } catch (_) {}
    if (existing) {
      existing.listRule = null;
      existing.viewRule = null;
      existing.createRule = null;
      existing.updateRule = null;
      existing.deleteRule = null;
      app.save(existing);
      return;
    }

    const collection = new BaseCollection("wesi_ai_connector_vault");
    collection.listRule = null;
    collection.viewRule = null;
    collection.createRule = null;
    collection.updateRule = null;
    collection.deleteRule = null;
    collection.fields.add(new TextField({name: "owner", required: true, max: 80}));
    collection.fields.add(new TextField({name: "rid", required: true, max: 180}));
    collection.fields.add(new TextField({name: "provider", required: true, max: 40}));
    collection.fields.add(new TextField({name: "kind", required: true, max: 40}));
    collection.fields.add(new TextField({name: "ciphertext", required: true, max: 262144}));
    collection.fields.add(new TextField({name: "expiresAt", max: 64}));
    collection.fields.add(new TextField({name: "stamp", required: true, max: 64}));
    collection.indexes = [
      "CREATE UNIQUE INDEX idx_wesi_ai_connector_owner_rid ON wesi_ai_connector_vault (owner, rid)",
      "CREATE INDEX idx_wesi_ai_connector_owner_kind ON wesi_ai_connector_vault (owner, kind, provider)"
    ];
    app.save(collection);
  },
  (app) => {
    // Credentials are deliberately not deleted by migration rollback.
    // A later migration must explicitly decide how to migrate/revoke them.
    console.log("wesi_ai_connector_vault rollback intentionally preserves encrypted credentials");
  },
);
