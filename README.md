# URWA (Universal Real World Asset Token)

A permissioned, regulatory-compliant ERC-20-style token inspired by **ERC-7943** for Real World Asset (RWA) compliance, identity verification, and asset recovery.

---

## 📐 Design Notes

### 1. Permissioned Transfer Guards (Allowlist)
- **Concept**: Transfers require both the sender and recipient to be explicitly approved by the asset issuer / compliance admin.
- **Functions**: `addToAllowList(address)`, `removeFromAllowList(address)`.
- **Validation**: Enforced via internal hooks `canSend()`, `canReceive()`, and `canTransfer()`. Reverts with `ERC7943CannotSend` / `ERC7943CannotReceive`.

### 2. Available Balance & Partial / Full Freezing
- **Available Balance**: Standard transfers only operate on available liquidity:
  $$\text{Available Balance} = \max(0, \text{balanceOf} - \text{frozenTokens})$$
- **Full Address Freeze (`freezeByAddress`)**: Locks the target's total current balance (used for accounts active in the allowlist).
- **Partial Amount Freeze (`setFrozenTokens` & `unfreezeToken`)**: Locks/unlocks specific token amounts for off-allowlist accounts.

### 3. Legal Recovery & Forced Transfer (`forcedTransfer`)
- **Compliance Primitive**: Allows the token owner (issuer or regulator) to repossess or recover funds from any account (e.g. lost keys, sanctions, court orders).
- **Freeze Reconciliation**: Automatically deducts from the frozen balance first, safely zeroing it if the transfer exceeds currently frozen amounts. Emits `forcedTransferSuccess`.

---

## 🛠 Usage & Testing

### Build
```shell
forge build
```

### Run Tests
```shell
forge test -vvv
```
