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

(define-constant min-stake u1000000)
(define-constant required-vouches u3)
(define-constant challenge-duration u144)

(define-data-var contract-paused bool false)
(define-data-var total-verified uint u0)
(define-data-var challenge-nonce uint u0)

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

(define-read-only (get-user-info (user principal))
  (map-get? user-registrations { user: user })
)

(define-read-only (is-verified (user principal))
  (match (map-get? user-registrations { user: user })
    user-data (is-eq (get verification-status user-data) "verified")
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

(define-public (register-human (proof-hash (buff 32)))
  (let (
    (user tx-sender)
    (stake-amount (stx-get-balance tx-sender))
  )
    (asserts! (not (var-get contract-paused)) (err u110))
    (asserts! (>= stake-amount min-stake) err-insufficient-stake)
    (asserts! (is-none (map-get? user-registrations { user: user })) err-already-exists)
    
    (try! (stx-transfer? min-stake tx-sender (as-contract tx-sender)))
    
    (map-set user-registrations
      { user: user }
      {
        stake-amount: min-stake,
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
        )
        (map-set user-registrations { user: target } updated-target-info)
      )
    )
    
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
