;; Automated Dividend Distribution Protocol (ADDP)
;; A dividend distribution system for real estate tokenization

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-SNAPSHOT-IN-PROGRESS (err u102))
(define-constant ERR-NO-DIVIDENDS (err u103))
(define-constant ERR-PAUSED (err u104))
(define-constant HOLDING-PERIOD (var-get minimum-holding-period))
(define-constant TRANSFER-DELAY-THRESHOLD u50000) ;; 1% of total supply for large transfers

;; Data Variables
(define-data-var token-name (string-ascii 32) "MetroSpace Property Token")
(define-data-var token-symbol (string-ascii 10) "MSPT")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var total-supply uint u50000000) ;; 50 million tokens
(define-data-var paused bool false)
(define-data-var minimum-holding-period uint u7) ;; 7 days minimum holding period
(define-data-var snapshot-in-progress bool false)
(define-data-var current-snapshot-id uint u0)
(define-data-var treasury-balance uint u0)

;; Data Maps
(define-map balances principal uint)
(define-map dividends-earned {holder: principal, snapshot-id: uint} uint)
(define-map claimed-dividends {holder: principal, snapshot-id: uint} bool)
(define-map last-deposit-height {holder: principal} uint)
(define-map token-approvals {owner: principal, spender: principal} uint)
(define-map snapshot-totals uint uint)

;; Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner))

(define-private (check-holding-period (holder principal))
    (let ((deposit-height (default-to u0 (map-get? last-deposit-height {holder: holder}))))
        (>= (- block-height deposit-height) HOLDING-PERIOD)))

(define-private (calculate-dividend-share (holder principal) (total-dividend uint))
    (let ((holder-balance (default-to u0 (map-get? balances holder))))
        (/ (* holder-balance total-dividend) (var-get total-supply))))

;; Public Functions

;; Initialize balances - can only be called once by contract owner
(define-public (initialize-protocol)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (map-set balances contract-owner (var-get total-supply))
        (ok true)))

;; Token Transfer
(define-public (transfer (amount uint) (sender principal) (recipient principal))
    (begin
        (asserts! (not (var-get paused)) ERR-PAUSED)
        (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
        (asserts! (>= (default-to u0 (map-get? balances sender)) amount) ERR-INVALID-AMOUNT)
        ;; Add recipient validation
        (asserts! (not (is-eq recipient sender)) ERR-INVALID-AMOUNT)
        (asserts! (is-valid-principal recipient) ERR-INVALID-AMOUNT)
        
        ;; Update balances
        (map-set balances
            sender
            (- (default-to u0 (map-get? balances sender)) amount))
        
        (map-set balances
            recipient
            (+ (default-to u0 (map-get? balances recipient)) amount))
        
        ;; Update deposit height for large transfers
        (if (>= amount TRANSFER-DELAY-THRESHOLD)
            (map-set last-deposit-height {holder: recipient} block-height)
            true)
        
        (ok true)))

;; Helper function to validate principal
(define-private (is-valid-principal (principal principal))
    (match (principal-destruct? principal)
        success true
        error false))

;; Deposit Revenue
(define-public (deposit-revenue)
    (begin
        (asserts! (not (var-get paused)) ERR-PAUSED)
        (var-set treasury-balance (+ (var-get treasury-balance) (stx-get-balance tx-sender)))
        (ok true)))

;; Take Snapshot
(define-public (take-snapshot)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (not (var-get snapshot-in-progress)) ERR-SNAPSHOT-IN-PROGRESS)
        
        ;; Start snapshot process
        (var-set snapshot-in-progress true)
        (var-set current-snapshot-id (+ (var-get current-snapshot-id) u1))
        
        ;; Record total supply at snapshot
        (map-set snapshot-totals (var-get current-snapshot-id) (var-get treasury-balance))
        
        ;; Reset treasury balance after snapshot
        (var-set treasury-balance u0)
        (var-set snapshot-in-progress false)
        (ok true)))

;; Claim Dividends
(define-public (claim-dividends (snapshot-id uint))
    (let ((holder tx-sender)
          (current-id (var-get current-snapshot-id)))
        ;; Add snapshot-id validation
        (asserts! (<= snapshot-id current-id) ERR-INVALID-AMOUNT)
        (let ((dividend-amount (default-to u0 (map-get? dividends-earned {holder: holder, snapshot-id: snapshot-id}))))
            (begin
                (asserts! (not (var-get paused)) ERR-PAUSED)
                (asserts! (> dividend-amount u0) ERR-NO-DIVIDENDS)
                (asserts! (not (default-to false (map-get? claimed-dividends {holder: holder, snapshot-id: snapshot-id}))) ERR-NO-DIVIDENDS)
                (asserts! (check-holding-period holder) ERR-NOT-AUTHORIZED)
                
                ;; Mark dividends as claimed
                (map-set claimed-dividends {holder: holder, snapshot-id: snapshot-id} true)
                
                ;; Transfer dividends and handle the response
                (let ((transfer-result (as-contract (stx-transfer? dividend-amount tx-sender holder))))
                    (asserts! (is-ok transfer-result) ERR-INVALID-AMOUNT)
                    (ok dividend-amount))))))

;; Emergency Functions
(define-public (pause-protocol)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set paused true)
        (ok true)))

(define-public (unpause-protocol)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set paused false)
        (ok true)))

;; Getter Functions
(define-read-only (get-balance (holder principal))
    (ok (default-to u0 (map-get? balances holder))))

(define-read-only (get-unclaimed-dividends (holder principal) (snapshot-id uint))
    (ok (default-to u0 (map-get? dividends-earned {holder: holder, snapshot-id: snapshot-id}))))

(define-read-only (get-current-snapshot-id)
    (ok (var-get current-snapshot-id)))

(define-read-only (get-treasury-balance)
    (ok (var-get treasury-balance)))

(define-read-only (is-protocol-paused)
    (ok (var-get paused)))