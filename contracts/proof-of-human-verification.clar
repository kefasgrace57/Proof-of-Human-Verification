(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-stake (err u103))
(define-constant err-not-verified (err u104))
(define-constant err-cannot-self-vouch (err u105))
(define-constant err-already-vouched (err u106))
(define-constant err-insufficient-vouches (err u107))
(define-constant err-invalid-challenge (err u108))
(define-constant err-challenge-expired (err u109))
(define-constant err-insufficient-reputation (err u112))
(define-constant err-verification-expired (err u113))
(define-constant err-too-early-renewal (err u114))
(define-constant err-insufficient-treasury (err u115))
(define-constant err-no-slashable-stake (err u116))
(define-constant err-already-badged (err u117))
(define-constant err-badge-not-found (err u118))

(define-constant minimum-stake u1000000)
(define-constant required-vouches u3)
(define-constant challenge-duration u144)
(define-constant base-reputation-score u500)
(define-constant max-reputation-score u1000)
(define-constant vouch-reward u50)
(define-constant challenge-success-reward u30)
(define-constant challenge-fail-penalty u20)
(define-constant verification-validity-period u8640)
(define-constant renewal-window u1440)
(define-constant renewal-discount-rate u2)
(define-constant slash-percentage u50)
(define-constant challenger-reward-percentage u30)
(define-constant treasury-percentage u70)

(define-data-var contract-paused bool false)
(define-data-var total-verified uint u0)
(define-data-var challenge-nonce uint u0)
(define-data-var community-treasury uint u0)
(define-data-var total-slashed uint u0)
(define-data-var total-rewards-paid uint u0)
(define-data-var badge-token-nonce uint u0)
(define-data-var total-badges uint u0)

(define-map user-registrations 
  { user: principal }
  {
    stake-amount: uint,
    registration-height: uint,
    verification-status: (string-ascii 20),
    vouches-received: uint,
    vouches-given: uint,
    challenge-response: (optional (buff 32))
  }
)

(define-read-only (has-badge (user principal))
  (is-some (map-get? badges-by-user { user: user }))
)

(define-read-only (get-badge-id (user principal))
  (match (map-get? badges-by-user { user: user })
    data (some (get token-id data))
    none
  )
)

(define-read-only (get-badge-owner (token-id uint))
  (match (map-get? badge-owners { token-id: token-id })
    data (some (get owner data))
    none
  )
)

(define-read-only (get-total-badges)
  (var-get total-badges)
)

(define-public (mint-badge)
  (let (
    (user tx-sender)
    (existing (map-get? badges-by-user { user: user }))
    (token-id (var-get badge-token-nonce))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-verified user) err-not-verified)
    (asserts! (is-none existing) err-already-badged)
    (map-set badges-by-user { user: user } { token-id: token-id })
    (map-set badge-owners { token-id: token-id } { owner: user })
    (var-set total-badges (+ (var-get total-badges) u1))
    (var-set badge-token-nonce (+ token-id u1))
    (ok token-id)
  )
)

(define-public (burn-badge (target principal))
  (let (
    (caller tx-sender)
    (record (map-get? badges-by-user { user: target }))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (or (is-eq caller contract-owner) (is-eq caller target)) err-owner-only)
    (match record
      data
        (let (
          (token-id (get token-id data))
        )
          (map-delete badges-by-user { user: target })
          (map-delete badge-owners { token-id: token-id })
          (var-set total-badges (- (var-get total-badges) u1))
          (ok token-id)
        )
      err-badge-not-found
    )
  )
)
(define-map vouches
  { voucher: principal, vouchee: principal }
  { vouch-height: uint }
)

(define-map challenges
  { challenge-id: uint }
  {
    challenger: principal,
    target: principal,
    challenge-data: (buff 32),
    created-height: uint,
    resolved: bool
  }
)

(define-map verification-timestamps
  { user: principal }
  { verified-at: uint }
)

(define-map reputation-scores
  { user: principal }
  {
    current-score: uint,
    total-vouches-given: uint,
    successful-challenges: uint,
    failed-challenges: uint,
    last-activity: uint
  }
)

(define-map badges-by-user
  { user: principal }
  { token-id: uint }
)

(define-map badge-owners
  { token-id: uint }
  { owner: principal }
)

(define-read-only (get-user-info (user principal))
  (map-get? user-registrations { user: user })
)

(define-read-only (is-verified (user principal))
  (match (map-get? user-registrations { user: user })
    user-data 
      (and 
        (is-eq (get verification-status user-data) "verified")
        (is-verification-valid user)
      )
    false
)
)

(define-map did-registry
  { user: principal }
  { did: (string-ascii 100) }
)

(define-read-only (get-did (user principal))
  (map-get? did-registry { user: user })
)

(define-public (set-did (did (string-ascii 100)))
  (let (
    (user tx-sender)
    (user-info (unwrap! (map-get? user-registrations { user: user }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status user-info) "verified") err-not-verified)
    (map-set did-registry { user: user } { did: did })
    (ok true)
  )
)

(define-read-only (is-verification-valid (user principal))
  (match (map-get? verification-timestamps { user: user })
    timestamp-data
      (let (
        (verified-at (get verified-at timestamp-data))
        (expiry-height (+ verified-at verification-validity-period))
      )
        (< stacks-block-height expiry-height)
      )
    false
  )
)

(define-read-only (get-verification-expiry (user principal))
  (match (map-get? verification-timestamps { user: user })
    timestamp-data
      (let (
        (verified-at (get verified-at timestamp-data))
      )
        (some (+ verified-at verification-validity-period))
      )
    none
  )
)

(define-read-only (can-renew-verification (user principal))
  (match (map-get? verification-timestamps { user: user })
    timestamp-data
      (let (
        (verified-at (get verified-at timestamp-data))
        (expiry-height (+ verified-at verification-validity-period))
        (renewal-start (- expiry-height renewal-window))
      )
        (and 
          (>= stacks-block-height renewal-start)
          (<= stacks-block-height expiry-height)
        )
      )
    false
  )
)

(define-read-only (get-verification-count)
  (var-get total-verified)
)

(define-read-only (has-vouched (voucher principal) (vouchee principal))
  (is-some (map-get? vouches { voucher: voucher, vouchee: vouchee }))
)

(define-read-only (get-challenge (challenge-id uint))
  (map-get? challenges { challenge-id: challenge-id })
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-community-treasury)
  (var-get community-treasury)
)

(define-read-only (get-slashing-stats)
  {
    total-slashed: (var-get total-slashed),
    total-rewards-paid: (var-get total-rewards-paid),
    treasury-balance: (var-get community-treasury)
  }
)

(define-read-only (get-reputation-score (user principal))
  (default-to 
    {
      current-score: base-reputation-score,
      total-vouches-given: u0,
      successful-challenges: u0,
      failed-challenges: u0,
      last-activity: u0
    }
    (map-get? reputation-scores { user: user })
  )
)

(define-read-only (calculate-trust-level (user principal))
  (let (
    (reputation (get-reputation-score user))
    (score (get current-score reputation))
  )
    (if (>= score u800)
      "high"
      (if (>= score u600)
        "medium"
        "low"
      )
    )
  )
)

(define-private (update-reputation-score (user principal) (score-change int))
  (let (
    (current-reputation (get-reputation-score user))
    (current-score (get current-score current-reputation))
    (new-score 
      (if (< score-change 0)
        (if (> current-score (to-uint (- 0 score-change)))
          (- current-score (to-uint (- 0 score-change)))
          u0
        )
        (if (> (+ current-score (to-uint score-change)) max-reputation-score)
          max-reputation-score
          (+ current-score (to-uint score-change))
        )
      )
    )
  )
    (map-set reputation-scores
      { user: user }
      (merge current-reputation 
        { 
          current-score: new-score,
          last-activity: stacks-block-height
        }
      )
    )
    (ok new-score)
  )
)

(define-public (register-human (proof-hash (buff 32)))
  (let (
    (user tx-sender)
    (stake-amount (stx-get-balance tx-sender))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (>= stake-amount minimum-stake) err-insufficient-stake)
    (asserts! (is-none (map-get? user-registrations { user: user })) err-already-exists)
    
    (try! (stx-transfer? minimum-stake tx-sender (as-contract tx-sender)))
    
    (map-set user-registrations
      { user: user }
      {
        stake-amount: minimum-stake,
        registration-height: stacks-block-height,
        verification-status: "pending",
        vouches-received: u0,
        vouches-given: u0,
        challenge-response: (some proof-hash)
      }
    )
    
    (ok true)
  )
)

(define-public (vouch-for-human (target principal))
  (let (
    (voucher tx-sender)
    (voucher-info (unwrap! (map-get? user-registrations { user: voucher }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status voucher-info) "verified") err-not-verified)
    (asserts! (not (is-eq voucher target)) err-cannot-self-vouch)
    (asserts! (is-none (map-get? vouches { voucher: voucher, vouchee: target })) err-already-vouched)
    
    (map-set vouches
      { voucher: voucher, vouchee: target }
      { vouch-height: stacks-block-height }
    )
    
    (map-set user-registrations
      { user: voucher }
      (merge voucher-info { vouches-given: (+ (get vouches-given voucher-info) u1) })
    )
    
    (let (
      (new-vouches (+ (get vouches-received target-info) u1))
      (updated-target-info (merge target-info { vouches-received: new-vouches }))
    )
      (if (>= new-vouches required-vouches)
        (begin
          (map-set user-registrations
            { user: target }
            (merge updated-target-info { verification-status: "verified" })
          )
          (map-set verification-timestamps
            { user: target }
            { verified-at: stacks-block-height }
          )
          (var-set total-verified (+ (var-get total-verified) u1))
          (unwrap-panic (update-reputation-score target (to-int base-reputation-score)))
        )
        (begin
          (map-set user-registrations { user: target } updated-target-info)
          u0
        )
      )
    )
    
    (unwrap-panic (update-reputation-score voucher (to-int vouch-reward)))
    (ok true)
  )
)

(define-public (create-challenge (target principal) (challenge-data (buff 32)))
  (let (
    (challenger tx-sender)
    (challenger-info (unwrap! (map-get? user-registrations { user: challenger }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
    (challenge-id (var-get challenge-nonce))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status challenger-info) "verified") err-not-verified)
    (asserts! (is-eq (get verification-status target-info) "verified") err-not-verified)
    (asserts! (not (is-eq challenger target)) err-cannot-self-vouch)
    
    (map-set challenges
      { challenge-id: challenge-id }
      {
        challenger: challenger,
        target: target,
        challenge-data: challenge-data,
        created-height: stacks-block-height,
        resolved: false
      }
    )
    
    (var-set challenge-nonce (+ challenge-id u1))
    (ok challenge-id)
  )
)

(define-public (respond-to-challenge (challenge-id uint) (response (buff 32)))
  (let (
    (responder tx-sender)
    (challenge-info (unwrap! (map-get? challenges { challenge-id: challenge-id }) err-not-found))
    (target (get target challenge-info))
    (created-height (get created-height challenge-info))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq responder target) err-not-verified)
    (asserts! (not (get resolved challenge-info)) err-invalid-challenge)
    (asserts! (<= (- stacks-block-height created-height) challenge-duration) err-challenge-expired)
    
    (map-set challenges
      { challenge-id: challenge-id }
      (merge challenge-info { resolved: true })
    )
    
    (let (
      (user-info (unwrap! (map-get? user-registrations { user: responder }) err-not-found))
    )
      (map-set user-registrations
        { user: responder }
        (merge user-info { challenge-response: (some response) })
      )
    )
    
    (ok true)
  )
)

(define-public (revoke-verification (target principal))
  (let (
    (challenger tx-sender)
    (challenger-info (unwrap! (map-get? user-registrations { user: challenger }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status challenger-info) "verified") err-not-verified)
    (asserts! (is-eq (get verification-status target-info) "verified") err-not-verified)
    (asserts! (not (is-eq challenger target)) err-cannot-self-vouch)
    
    (map-set user-registrations
      { user: target }
      (merge target-info { verification-status: "revoked" })
    )
    
    (var-set total-verified (- (var-get total-verified) u1))
    (ok true)
  )
)

(define-public (withdraw-stake)
  (let (
    (user tx-sender)
    (user-info (unwrap! (map-get? user-registrations { user: user }) err-not-found))
    (stake-amount (get stake-amount user-info))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (not (is-eq (get verification-status user-info) "verified")) err-not-verified)
    
    (try! (as-contract (stx-transfer? stake-amount tx-sender user)))
    
    (map-delete user-registrations { user: user })
    (ok stake-amount)
  )
)

(define-public (bootstrap-verification)
  (let (
    (user tx-sender)
  )
    (asserts! (is-eq user contract-owner) err-owner-only)
    (asserts! (is-none (map-get? user-registrations { user: user })) err-already-exists)
    
    (map-set user-registrations
      { user: user }
      {
        stake-amount: u0,
        registration-height: stacks-block-height,
        verification-status: "verified",
        vouches-received: u0,
        vouches-given: u0,
        challenge-response: none
      }
    )
    
    (map-set verification-timestamps
      { user: user }
      { verified-at: stacks-block-height }
    )
    
    (var-set total-verified u1)
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (emergency-withdraw (user principal))
  (let (
    (user-info (unwrap! (map-get? user-registrations { user: user }) err-not-found))
    (stake-amount (get stake-amount user-info))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get contract-paused) (err u111))
    
    (try! (as-contract (stx-transfer? stake-amount tx-sender user)))
    (map-delete user-registrations { user: user })
    (ok stake-amount)
  )
)

(define-public (update-challenge-stats (target principal) (success bool))
  (let (
    (challenger tx-sender)
    (challenger-info (unwrap! (map-get? user-registrations { user: challenger }) err-not-found))
    (current-reputation (get-reputation-score challenger))
    (score-change (if success challenge-success-reward challenge-fail-penalty))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status challenger-info) "verified") err-not-verified)
    
    (if success
      (map-set reputation-scores
        { user: challenger }
        (merge current-reputation { successful-challenges: (+ (get successful-challenges current-reputation) u1) })
      )
      (map-set reputation-scores
        { user: challenger }
        (merge current-reputation { failed-challenges: (+ (get failed-challenges current-reputation) u1) })
      )
    )
    
    (unwrap-panic (update-reputation-score challenger (to-int score-change)))
    (ok true)
  )
)

(define-public (verify-high-reputation-user (target principal))
  (let (
    (verifier tx-sender)
    (verifier-info (unwrap! (map-get? user-registrations { user: verifier }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
    (verifier-trust (calculate-trust-level verifier))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status verifier-info) "verified") err-not-verified)
    (asserts! (is-eq verifier-trust "high") err-insufficient-reputation)
    (asserts! (is-eq (get verification-status target-info) "pending") err-not-found)
    
    (map-set user-registrations
      { user: target }
      (merge target-info { verification-status: "verified" })
    )
    
    (map-set verification-timestamps
      { user: target }
      { verified-at: stacks-block-height }
    )
    
    (var-set total-verified (+ (var-get total-verified) u1))
    (unwrap-panic (update-reputation-score target (to-int base-reputation-score)))
    (unwrap-panic (update-reputation-score verifier (to-int (* vouch-reward u2))))
    (ok true)
  )
)

(define-public (renew-verification)
  (let (
    (user tx-sender)
    (user-info (unwrap! (map-get? user-registrations { user: user }) err-not-found))
    (renewal-fee (/ minimum-stake renewal-discount-rate))
    (user-balance (stx-get-balance tx-sender))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status user-info) "verified") err-not-verified)
    (asserts! (can-renew-verification user) err-too-early-renewal)
    (asserts! (>= user-balance renewal-fee) err-insufficient-stake)
    
    (try! (stx-transfer? renewal-fee tx-sender (as-contract tx-sender)))
    
    (map-set verification-timestamps
      { user: user }
      { verified-at: stacks-block-height }
    )
    
    (unwrap-panic (update-reputation-score user (to-int vouch-reward)))
    (ok true)
  )
)

(define-public (extend-verification (target principal))
  (let (
    (extender tx-sender)
    (extender-info (unwrap! (map-get? user-registrations { user: extender }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
    (extender-trust (calculate-trust-level extender))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status extender-info) "verified") err-not-verified)
    (asserts! (is-verification-valid extender) err-verification-expired)
    (asserts! (is-eq (get verification-status target-info) "verified") err-not-verified)
    (asserts! (is-eq extender-trust "high") err-insufficient-reputation)
    (asserts! (not (is-eq extender target)) err-cannot-self-vouch)
    (asserts! (not (is-verification-valid target)) err-already-exists)
    
    (map-set verification-timestamps
      { user: target }
      { verified-at: stacks-block-height }
    )
    
    (unwrap-panic (update-reputation-score extender (to-int challenge-success-reward)))
    (unwrap-panic (update-reputation-score target (to-int vouch-reward)))
    (ok true)
  )
)

(define-public (slash-and-revoke (target principal))
  (let (
    (slasher tx-sender)
    (slasher-info (unwrap! (map-get? user-registrations { user: slasher }) err-not-found))
    (target-info (unwrap! (map-get? user-registrations { user: target }) err-not-found))
    (target-stake (get stake-amount target-info))
    (slash-amount (/ (* target-stake slash-percentage) u100))
    (challenger-reward (/ (* slash-amount challenger-reward-percentage) u100))
    (treasury-amount (/ (* slash-amount treasury-percentage) u100))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status slasher-info) "verified") err-not-verified)
    (asserts! (is-verification-valid slasher) err-verification-expired)
    (asserts! (is-eq (get verification-status target-info) "verified") err-not-verified)
    (asserts! (not (is-eq slasher target)) err-cannot-self-vouch)
    (asserts! (> target-stake u0) err-no-slashable-stake)
    
    (map-set user-registrations
      { user: target }
      (merge target-info 
        { 
          verification-status: "revoked",
          stake-amount: (- target-stake slash-amount)
        }
      )
    )
    
    (try! (as-contract (stx-transfer? challenger-reward tx-sender slasher)))
    
    (var-set community-treasury (+ (var-get community-treasury) treasury-amount))
    (var-set total-slashed (+ (var-get total-slashed) slash-amount))
    (var-set total-rewards-paid (+ (var-get total-rewards-paid) challenger-reward))
    (var-set total-verified (- (var-get total-verified) u1))
    
    (unwrap-panic (update-reputation-score slasher (to-int challenge-success-reward)))
    (unwrap-panic (update-reputation-score target (- 0 (to-int challenge-fail-penalty))))
    (ok slash-amount)
  )
)

(define-public (claim-treasury-reward (amount uint))
  (let (
    (claimer tx-sender)
    (claimer-info (unwrap! (map-get? user-registrations { user: claimer }) err-not-found))
    (claimer-reputation (get-reputation-score claimer))
    (claimer-score (get current-score claimer-reputation))
    (treasury-balance (var-get community-treasury))
    (max-claimable (/ (* treasury-balance claimer-score) max-reputation-score))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (is-eq (get verification-status claimer-info) "verified") err-not-verified)
    (asserts! (is-verification-valid claimer) err-verification-expired)
    (asserts! (<= amount max-claimable) err-insufficient-treasury)
    (asserts! (<= amount treasury-balance) err-insufficient-treasury)
    
    (try! (as-contract (stx-transfer? amount tx-sender claimer)))
    
    (var-set community-treasury (- treasury-balance amount))
    (var-set total-rewards-paid (+ (var-get total-rewards-paid) amount))
    (ok amount)
  )
)

(define-public (distribute-treasury-rewards (recipients (list 20 principal)))
  (let (
    (distributor tx-sender)
    (treasury-balance (var-get community-treasury))
    (per-recipient-amount (/ treasury-balance (len recipients)))
  )
    (asserts! (is-eq distributor contract-owner) err-owner-only)
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (> treasury-balance u0) err-insufficient-treasury)
    (asserts! (> (len recipients) u0) err-not-found)
    
    (fold process-reward-distribution recipients (ok u0))
  )
)

(define-private (process-reward-distribution (recipient principal) (previous-result (response uint uint)))
  (let (
    (treasury-balance (var-get community-treasury))
    (reward-amount (/ treasury-balance u20))
  )
    (match previous-result
      success
        (match (map-get? user-registrations { user: recipient })
          user-data
            (if (and 
                  (is-eq (get verification-status user-data) "verified")
                  (is-verification-valid recipient)
                  (> treasury-balance reward-amount))
              (begin
                (unwrap-panic (as-contract (stx-transfer? reward-amount tx-sender recipient)))
                (var-set community-treasury (- treasury-balance reward-amount))
                (var-set total-rewards-paid (+ (var-get total-rewards-paid) reward-amount))
                (ok (+ success reward-amount))
              )
              (ok success)
            )
          (ok success)
        )
      error (err error)
    )
  )
)
