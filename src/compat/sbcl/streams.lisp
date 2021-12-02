(defpackage :alive/streams
    (:use :cl)
    (:export :rt-stream
             :eof-p
    ))

(in-package :alive/streams)


(defclass rt-stream (sb-gray:fundamental-character-output-stream)
    ((buffer :accessor buffer
             :initform ""
             :initarg :buffer
     )
     (stdout :accessor stdout
             :initform nil
             :initarg :stdout
     )
     (closed-p :accessor closed-p
               :initform nil
               :initarg :closed-p
     )
     (eof-p :accessor eof-p
            :initform nil
            :initarg :eof-p
     )
     (lock :accessor lock
           :initform (bt:make-lock)
           :initarg :lock
     )
     (cond-var :accessor cond-var
               :initform (bt:make-condition-variable)
               :initarg :cond-var
     )))


(defmethod stream-element-type ((obj rt-stream))
    'character
)


(defmethod close ((obj rt-stream) &key abort)
    (declare (ignore abort))

    (bt:with-lock-held ((lock obj))
                       (setf (closed-p obj) T)
                       (bt:condition-notify (cond-var obj))
    ))


(defmethod sb-gray:stream-write-char ((obj rt-stream) ch)
    (bt:with-lock-held ((lock obj))
                       (when ch
                             (setf (buffer obj) (format nil "~A~A" (buffer obj) ch))
                             (bt:condition-notify (cond-var obj))
                       )))


(defun end-stream (obj)
    (setf (eof-p obj) T)
    :eof
)


(defun next-buffer-char (obj)
    (bt:with-lock-held ((lock obj))
                       (let ((ch (elt (buffer obj) 0)))
                           (setf (buffer obj)
                                 (subseq (buffer obj) 1)
                           )
                           (if ch ch (end-stream obj))
                       )))


(defun flush-read-stream (obj)
    (loop :with counter := 10
          :with ch := nil
          :until (zerop counter)
          :do (if (zerop (length (buffer obj)))
                  (progn (decf counter)
                         (sleep 0.01)
                  )
                  (progn (setf counter 10)
                         (setf ch (next-buffer-char obj))
                  ))
          :finally (return (if ch ch (end-stream obj)))
    ))


(defun next-read-char (obj)
    (when (zerop (length (buffer obj)))
          (bt:with-lock-held ((lock obj))
                             (bt:condition-wait (cond-var obj) (lock obj))
          ))

    (if (closed-p obj)
        (flush-read-stream obj)
        (next-buffer-char obj)
    ))


(defmethod sb-gray:stream-read-char ((obj rt-stream))
    (if (closed-p obj)
        (flush-read-stream obj)
        (next-read-char obj)
    ))


(defmethod sb-gray:stream-read-line ((obj rt-stream))
    (bt:with-lock-held ((lock obj))
                       (loop :until (or (closed-p obj)
                                        (position #\linefeed (buffer obj))
                                    )
                             :do (bt:condition-wait (cond-var obj) (lock obj))
                       )

                       (if (closed-p obj)
                           (end-stream obj)
                           (let* ((pos (position #\linefeed (buffer obj)))
                                  (line (subseq (buffer obj) 0 pos))
                                 )
                               (setf (buffer obj) (subseq (buffer obj) (+ pos 1)))
                               line
                           ))))
