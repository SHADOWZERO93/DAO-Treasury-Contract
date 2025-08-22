;; DAO Treasury Contract
;; Decentralized treasury management with proposal system
;; Built with Clarity for Stacks blockchain

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-proposal-not-found (err u104))
(define-constant err-proposal-already-executed (err u105))
(define-constant err-insufficient-votes (err u106))

;; Data variables
(define-data-var treasury-balance uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var voting-threshold uint u3) ;; Minimum votes needed to pass

;; Proposal structure
(define-map proposals
  uint
  {
    recipient: principal,
    amount: uint,
    description: (string-ascii 256),
    votes: uint,
    executed: bool,
    proposer: principal
  })

;; Voting tracking
(define-map votes 
  {proposal-id: uint, voter: principal} 
  bool)

;; DAO members
(define-map dao-members principal bool)

;; Initialize DAO members (owner is first member)
(map-set dao-members contract-owner true)

;; Function 1: Create Proposal
;; Allows DAO members to create funding proposals
(define-public (create-proposal (recipient principal) (amount uint) (description (string-ascii 256)))
  (let 
    (
      (proposal-id (+ (var-get proposal-counter) u1))
    )
    (begin
      ;; Check if sender is DAO member
      (asserts! (default-to false (map-get? dao-members tx-sender)) err-not-authorized)
      ;; Validate amount
      (asserts! (> amount u0) err-invalid-amount)
      ;; Check treasury has sufficient funds
      (asserts! (>= (var-get treasury-balance) amount) err-insufficient-funds)
      
      ;; Create the proposal
      (map-set proposals proposal-id {
        recipient: recipient,
        amount: amount,
        description: description,
        votes: u0,
        executed: false,
        proposer: tx-sender
      })
      
      ;; Increment proposal counter
      (var-set proposal-counter proposal-id)
      
      ;; Print event
      (print {
        event: "proposal-created",
        proposal-id: proposal-id,
        recipient: recipient,
        amount: amount,
        proposer: tx-sender
      })
      
      (ok proposal-id))))

;; Function 2: Execute Proposal
;; Executes proposals that meet voting threshold and transfers funds
(define-public (execute-proposal (proposal-id uint))
  (let 
    (
      (proposal-data (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (begin
      ;; Check if proposal exists and not already executed
      (asserts! (not (get executed proposal-data)) err-proposal-already-executed)
      ;; Check if proposal has enough votes
      (asserts! (>= (get votes proposal-data) (var-get voting-threshold)) err-insufficient-votes)
      ;; Check treasury has sufficient funds
      (asserts! (>= (var-get treasury-balance) (get amount proposal-data)) err-insufficient-funds)
      
      ;; Transfer STX to recipient
      (try! (as-contract (stx-transfer? (get amount proposal-data) tx-sender (get recipient proposal-data))))
      
      ;; Update treasury balance
      (var-set treasury-balance (- (var-get treasury-balance) (get amount proposal-data)))
      
      ;; Mark proposal as executed
      (map-set proposals proposal-id (merge proposal-data {executed: true}))
      
      ;; Print event
      (print {
        event: "proposal-executed",
        proposal-id: proposal-id,
        recipient: (get recipient proposal-data),
        amount: (get amount proposal-data)
      })
      
      (ok true))))

;; Helper functions for reading contract state

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (ok (map-get? proposals proposal-id)))

;; Get treasury balance
(define-read-only (get-treasury-balance)
  (ok (var-get treasury-balance)))

;; Get voting threshold
(define-read-only (get-voting-threshold)
  (ok (var-get voting-threshold)))

;; Check if address is DAO member
(define-read-only (is-dao-member (member principal))
  (ok (default-to false (map-get? dao-members member))))

;; Get total proposals count
(define-read-only (get-proposal-count)
  (ok (var-get proposal-counter)))

;; Deposit STX to treasury (anyone can contribute)
(define-public (deposit-to-treasury (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (print {event: "treasury-deposit", amount: amount, depositor: tx-sender})
    (ok true)))

;; Vote on proposal (simplified - DAO members only)
(define-public (vote-on-proposal (proposal-id uint))
  (let 
    (
      (proposal-data (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
      (vote-key {proposal-id: proposal-id, voter: tx-sender})
    )
    (begin
      ;; Check if sender is DAO member
      (asserts! (default-to false (map-get? dao-members tx-sender)) err-not-authorized)
      ;; Check if already voted
      (asserts! (is-none (map-get? votes vote-key)) err-not-authorized)
      ;; Check proposal not executed
      (asserts! (not (get executed proposal-data)) err-proposal-already-executed)
      
      ;; Record vote
      (map-set votes vote-key true)
      
      ;; Increment vote count
      (map-set proposals proposal-id 
        (merge proposal-data {votes: (+ (get votes proposal-data) u1)}))
      
      (print {event: "vote-cast", proposal-id: proposal-id, voter: tx-sender})
      (ok true))))

;; Add DAO member (owner only)
(define-public (add-dao-member (new-member principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set dao-members new-member true)
    (print {event: "member-added", member: new-member})
    (ok true)))