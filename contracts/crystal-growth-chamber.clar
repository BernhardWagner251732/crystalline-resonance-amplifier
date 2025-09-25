
;; title: crystal-growth-chamber
;; version: 1.0.0
;; summary: Precision laboratory system for growing acoustic crystals with specific frequency response characteristics
;; description: This contract manages the growth, certification, and tracking of acoustic crystals used in musical instruments

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_CRYSTAL (err u101))
(define-constant ERR_CRYSTAL_EXISTS (err u102))
(define-constant ERR_CRYSTAL_NOT_FOUND (err u103))
(define-constant ERR_INVALID_FREQUENCY (err u104))
(define-constant ERR_GROWTH_IN_PROGRESS (err u105))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u106))
(define-constant ERR_CERTIFICATION_FAILED (err u107))

;; minimum and maximum frequency ranges (Hz)
(define-constant MIN_FREQUENCY u20)
(define-constant MAX_FREQUENCY u20000)
(define-constant MIN_GROWTH_TIME u24) ;; minimum 24 hours
(define-constant BASE_GROWTH_COST u1000000) ;; 1 STX in microSTX

;; data vars
(define-data-var crystal-counter uint u0)
(define-data-var total-crystals-grown uint u0)
(define-data-var contract-balance uint u0)
(define-data-var maintenance-mode bool false)

;; crystal structure definition
(define-map crystals uint {
    owner: principal,
    name: (string-ascii 64),
    frequency-min: uint,
    frequency-max: uint,
    growth-started: uint,
    growth-completed: (optional uint),
    quality-grade: (string-ascii 16),
    certification-status: (string-ascii 16),
    acoustic-properties: (string-ascii 128),
    creation-cost: uint,
    certified-by: (optional principal)
})

;; growth queue for tracking active growth processes
(define-map growth-queue uint {
    crystal-id: uint,
    estimated-completion: uint,
    temperature: uint,
    humidity: uint,
    growth-medium: (string-ascii 32),
    monitoring-frequency: uint
})

;; laboratory configuration
(define-map lab-config (string-ascii 32) {
    parameter-value: uint,
    last-updated: uint,
    updated-by: principal
})

;; certification authorities
(define-map certified-authorities principal {
    authority-name: (string-ascii 64),
    specialization: (string-ascii 64),
    certification-count: uint,
    active: bool
})

;; public functions

;; Initialize a new crystal growth process
(define-public (grow-crystal 
    (crystal-name (string-ascii 64))
    (freq-min uint)
    (freq-max uint)
    (quality-target (string-ascii 16))
    (acoustic-props (string-ascii 128)))
    (let (
        (crystal-id (+ (var-get crystal-counter) u1))
        (growth-cost (calculate-growth-cost freq-min freq-max quality-target))
        (current-height stacks-block-height)
    )
    (asserts! (not (var-get maintenance-mode)) (err u108))
    (asserts! (>= freq-min MIN_FREQUENCY) ERR_INVALID_FREQUENCY)
    (asserts! (<= freq-max MAX_FREQUENCY) ERR_INVALID_FREQUENCY)
    (asserts! (< freq-min freq-max) ERR_INVALID_FREQUENCY)
    (asserts! (>= (stx-get-balance tx-sender) growth-cost) ERR_INSUFFICIENT_PAYMENT)
    
    ;; Transfer payment for crystal growth
    (try! (stx-transfer? growth-cost tx-sender (as-contract tx-sender)))
    
    ;; Create crystal record
    (map-set crystals crystal-id {
        owner: tx-sender,
        name: crystal-name,
        frequency-min: freq-min,
        frequency-max: freq-max,
        growth-started: current-height,
        growth-completed: none,
        quality-grade: "pending",
        certification-status: "growing",
        acoustic-properties: acoustic-props,
        creation-cost: growth-cost,
        certified-by: none
    })
    
    ;; Add to growth queue
    (map-set growth-queue crystal-id {
        crystal-id: crystal-id,
        estimated-completion: (+ current-height (* u144 MIN_GROWTH_TIME)), ;; 24 hours in blocks
        temperature: u295, ;; 22 degrees C in Kelvin * 10
        humidity: u55, ;; 55% humidity
        growth-medium: "silicon-carbide",
        monitoring-frequency: u6 ;; every 6 blocks
    })
    
    ;; Update counters
    (var-set crystal-counter crystal-id)
    (var-set total-crystals-grown (+ (var-get total-crystals-grown) u1))
    (var-set contract-balance (+ (var-get contract-balance) growth-cost))
    
    (ok crystal-id)
    )
)

;; Complete crystal growth process
(define-public (complete-growth (crystal-id uint))
    (let (
        (crystal-data (unwrap! (map-get? crystals crystal-id) ERR_CRYSTAL_NOT_FOUND))
        (growth-data (unwrap! (map-get? growth-queue crystal-id) ERR_CRYSTAL_NOT_FOUND))
        (current-height stacks-block-height)
    )
    (asserts! (is-eq (get owner crystal-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (>= current-height (get estimated-completion growth-data)) ERR_GROWTH_IN_PROGRESS)
    (asserts! (is-none (get growth-completed crystal-data)) ERR_CRYSTAL_EXISTS)
    
    ;; Update crystal as completed
    (map-set crystals crystal-id (merge crystal-data {
        growth-completed: (some current-height),
        quality-grade: (determine-quality-grade (get frequency-min crystal-data) (get frequency-max crystal-data)),
        certification-status: "ready-for-cert"
    }))
    
    ;; Remove from growth queue
    (map-delete growth-queue crystal-id)
    
    (ok true)
    )
)

;; Certify a completed crystal
(define-public (certify-crystal (crystal-id uint) (certification-grade (string-ascii 16)))
    (let (
        (crystal-data (unwrap! (map-get? crystals crystal-id) ERR_CRYSTAL_NOT_FOUND))
        (authority-data (unwrap! (map-get? certified-authorities tx-sender) ERR_UNAUTHORIZED))
    )
    (asserts! (get active authority-data) ERR_UNAUTHORIZED)
    (asserts! (is-some (get growth-completed crystal-data)) ERR_CRYSTAL_NOT_FOUND)
    (asserts! (is-eq (get certification-status crystal-data) "ready-for-cert") ERR_CERTIFICATION_FAILED)
    
    ;; Update crystal certification
    (map-set crystals crystal-id (merge crystal-data {
        certification-status: certification-grade,
        certified-by: (some tx-sender)
    }))
    
    ;; Update authority certification count
    (map-set certified-authorities tx-sender (merge authority-data {
        certification-count: (+ (get certification-count authority-data) u1)
    }))
    
    (ok true)
    )
)

;; Add certified authority (only contract owner)
(define-public (add-authority 
    (authority principal) 
    (name (string-ascii 64)) 
    (specialization (string-ascii 64)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set certified-authorities authority {
            authority-name: name,
            specialization: specialization,
            certification-count: u0,
            active: true
        })
        (ok true)
    )
)

;; Update laboratory configuration
(define-public (update-lab-config 
    (param-name (string-ascii 32)) 
    (param-value uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set lab-config param-name {
            parameter-value: param-value,
            last-updated: stacks-block-height,
            updated-by: tx-sender
        })
        (ok true)
    )
)

;; Emergency maintenance mode toggle
(define-public (toggle-maintenance-mode)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set maintenance-mode (not (var-get maintenance-mode)))
        (ok (var-get maintenance-mode))
    )
)

;; read only functions

;; Get crystal details
(define-read-only (get-crystal-specs (crystal-id uint))
    (map-get? crystals crystal-id)
)

;; Get growth queue status
(define-read-only (get-growth-status (crystal-id uint))
    (map-get? growth-queue crystal-id)
)

;; Get laboratory statistics
(define-read-only (get-lab-stats)
    {
        total-crystals: (var-get total-crystals-grown),
        contract-balance: (var-get contract-balance),
        maintenance-mode: (var-get maintenance-mode),
        next-crystal-id: (+ (var-get crystal-counter) u1)
    }
)

;; Check if crystal is ready for harvest
(define-read-only (is-ready-for-harvest (crystal-id uint))
    (match (map-get? growth-queue crystal-id)
        growth-data (>= stacks-block-height (get estimated-completion growth-data))
        false
    )
)

;; Get authority information
(define-read-only (get-authority-info (authority principal))
    (map-get? certified-authorities authority)
)

;; Calculate frequency response quality
(define-read-only (calculate-frequency-response (freq-min uint) (freq-max uint))
    (let (
        (frequency-range (- freq-max freq-min))
        (midpoint (/ (+ freq-max freq-min) u2))
    )
    {
        range: frequency-range,
        midpoint: midpoint,
        quality-score: (/ frequency-range u100)
    }
    )
)

;; private functions

;; Calculate growth cost based on parameters
(define-private (calculate-growth-cost 
    (freq-min uint) 
    (freq-max uint) 
    (quality-target (string-ascii 16)))
    (let (
        (frequency-complexity (- freq-max freq-min))
        (quality-multiplier (if (is-eq quality-target "premium") u2 u1))
    )
    (* BASE_GROWTH_COST quality-multiplier (/ frequency-complexity u1000))
    )
)

;; Determine quality grade based on frequency range
(define-private (determine-quality-grade (freq-min uint) (freq-max uint))
    (let ((range (- freq-max freq-min)))
        (if (> range u10000) "premium"
            (if (> range u5000) "professional"
                (if (> range u2000) "standard"
                    "basic"
                )
            )
        )
    )
)
