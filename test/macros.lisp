;;;; macros.lisp --- Unit tests for the macros provided by the more-conditions system.
;;;;
;;;; Copyright (C) 2012, 2013 Jan Moringen
;;;;
;;;; Author: Jan Moringen <jmoringe@techfak.uni-bielefeld.de>

(cl:in-package #:more-conditions.test)

(deftestsuite macros-root (root)
  ()
  (:setup
   ;; Without eval, causes failed aver in SBCL.
   (eval
    `(progn
       (define-condition source-condition (error)
         ())
       (define-condition target-condition/no-cause (error)
         ((slot :initarg  :slot
                :reader   target-condition-slot
                :initform :default)))
       (define-condition target-condition/cause (error
                                                 chainable-condition)
         ((slot :initarg  :slot
                :reader   target-condition-slot
                :initform :default))))))
  (:documentation
   "Test suite for macros provided by the more-conditions
system."))

(deftestsuite with-condition-translation-root (macros-root)
  ()
  (:documentation
   "Unit tests for `with-condition-translation' macro."))

(addtest (with-condition-translation-root
          :documentation
          "Smoke test for translating `error' to a condition class
without cause storage via `with-condition-translation'.")
  smoke/no-cause

  (let ((source (make-condition 'source-condition)))
   (handler-case
       (with-condition-translation (((error target-condition/no-cause)))
         (error source))
     (target-condition/no-cause (condition)
       (ensure-same (target-condition-slot condition) :default)))))

(addtest (with-condition-translation-root
          :documentation
           "Smoke test for translating `error' to a condition class
with cause storage via `with-condition-translation'.")
  smoke/cause

  (let ((source (make-condition 'source-condition)))
    (handler-case
        (with-condition-translation (((error target-condition/cause)))
          (error source))
      (target-condition/cause (condition)
        (ensure-same (target-condition-slot condition) :default)
        (ensure-same (cause                 condition) source)
        (ensure-same (root-cause            condition) source)))))

(deftestsuite define-condition-translating-method-root (macros-root)
  ()
  (:setup
   (defmethod foo ((bar t))
     (error bar))
   (define-condition-translating-method foo ((bar t))
     ((error target-condition/cause)))

   (defmethod foo/initargs ((bar t))
     (error bar))
   (define-condition-translating-method foo/initargs ((bar t))
     ((error target-condition/no-cause
       :cause-initarg nil)
      :slot :supplied)))
  (:teardown
   (fmakunbound 'foo)
   (fmakunbound 'foo/initargs))
  (:documentation
   "Test suite for the `define-condition-translating-method' macro."))

(addtest (define-condition-translating-method-root
          :documentation
          "Smoke test for defining a condition translating method with
capturing of the causing condition via
`define-condition-translating-method.'")
  smoke/cause

  (let ((source (make-condition 'source-condition)))
    (handler-case
        (foo source)
      (target-condition/cause (condition)
        (ensure-same (target-condition-slot condition) :default)
        (ensure-same (cause                 condition) source)
        (ensure-same (root-cause            condition) source)))))

(addtest (define-condition-translating-method-root
          :documentation
             "Smoke test for defining a condition translating method
which adds additional initargs via
`define-condition-translating-method.'")
  smoke/initargs

  (let ((source (make-condition 'source-condition)))
    (handler-case
        (foo/initargs source)
      (target-condition/no-cause (condition)
        (ensure-same (target-condition-slot condition) :supplied)))))

;;; `error-behavior-restart-case'

(deftestsuite error-behavior-restart-case-root (macros-root)
  ()
  (:documentation
   "Unit tests for the `error-behavior-restart-case' macro."))

(addtest (error-behavior-restart-case-root
          :documentation
          "Smoke test for the `error-behavior-restart-case' macro.")
  smoke

  (ensure-cases (policy expected)

      `((,#'error    error)
        (error       error)
        (,#'warn     nil)
        (warn        nil)
        (,#'continue :continue)
        (continue    :continue)
        (nil         nil)
        (:foo        :foo)
        (1           1))

    (flet ((do-it (warning?)
             (macrolet
                 ((body (warning?)
                    `(error-behavior-restart-case
                         (policy
                          (simple-error
                           :format-control   "Example error: ~A"
                           :format-arguments (list :foo))
                          ,@(when warning?
                              '(:warning-condition simple-warning))
                          :allow-other-values? t)
                       (continue (&optional condition)
                         :continue))))
               (if warning? (body t) (body nil)))))

      (case expected
        (error (ensure-condition 'error (do-it t)))
        (t     (ensure-same (do-it t) expected)))
      (case expected
        (error (ensure-condition 'error (do-it nil)))
        (t     (cond
                 ((member policy `(warn ,#'warn))
                  (ensure-condition 'program-error (do-it nil)))
                 (t
                  (ensure-same (do-it nil) expected))))))))

;;; Progress macros

(deftestsuite with-trivial-progress-root (macros-root)
  ()
  (:documentation
   "Unit tests for the `with-trivial-progress' macro."))

(addtest (with-trivial-progress-root
          :documentation
          "Smoke test for the `with-trivial-progress' macro.")
  smoke

  (macrolet
      ((test (&rest args)
         `(let ((conditions '()))
            (handler-bind ((progress-condition
                             (lambda (condition)
                               (push condition conditions))))
              (with-trivial-progress ,args))
            (mapc #'princ-to-string conditions)
            (ensure-same 2 (length conditions) :test #'=))))

    (test :foo)
    (test :foo "bar")
    (test :foo "bar: ~A" :baz)
    (test :foo 'simple-progress-condition)
    (test :foo 'simple-progress-condition
               :format-control "bar")
    (test :foo 'simple-progress-condition
               :format-control   "bar: ~A"
               :format-arguments '(:baz))))

(deftestsuite with-sequence-progress-root (macros-root)
  ()
  (:documentation
   "Unit tests for the `with-sequence-progress' macro."))

(addtest (with-sequence-progress-root
           :documentation
           "Smoke test for the `with-sequence-progress' macro.")
  smoke

  (macrolet
      ((test ((expected-conditions operation sequence &rest args) &body body)
         `(let ((conditions '()))
            (handler-bind ((progress-condition
                             (lambda (condition)
                               (push condition conditions))))
              (let ((sequence ,sequence))
                (with-sequence-progress (,operation sequence ,@(rest args))
                  ,@body)))
            (mapc #'princ-to-string conditions)
            (ensure-same ,expected-conditions (length conditions)
                         :test #'=))))

    ;; `progress'
    (test (2 :foo '(1 2)) (progress))
    (test (2 :foo '(1 2)) (progress "bar"))
    (test (2 :foo '(1 2)) (progress "bar: ~A" :baz))
    (test (2 :foo '(1 2)) (progress 'simple-progress-condition))
    (test (2 :foo '(1 2))
      (progress 'simple-progress-condition :format-control "bar"))
    (test (2 :foo '(1 2))
      (progress 'simple-progress-condition
                :format-control   "bar: ~A"
                :format-arguments '(:baz)))

    ;; `progressing'
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo) sequence))
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo "bar") sequence))
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo "bar: ~A" :baz) sequence))
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo 'simple-progress-condition)
            sequence))
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo 'simple-progress-condition
                              :format-control "bar")
            sequence))
    (test (3 :foo '(1 2))
      (mapc (progressing #'1+ :foo 'simple-progress-condition
                              :format-control   "bar: ~A"
                              :format-arguments '(:baz))
            sequence))))
