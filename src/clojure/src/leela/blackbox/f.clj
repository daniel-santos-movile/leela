(ns leela.blackbox.f
  (:use     [clojure.tools.logging :only [warn]])
  (:require [clojure.data.json :as json]))

(defmacro forever [& body]
  `(forever-with (fn [] true) ~@body))

(defmacro forever-with [check & body]
  `(while (~check) ~@body))

; http://stackoverflow.com/questions/1879885/clojure-how-to-to-recur-upon-exception
(defn retry-on-error1 [n f]
  (loop [n n]
    (if-let [result (try
                      [(f)]
                      (catch Exception e
                        (when (zero? n)
                          (throw e))))]
      (result 0)
      (recur (dec n)))))

(defmacro retry-on-error [n & body]
  `(retry-on-error1 ~n (fn [] ~@body)))

(defmacro supervise [& body]
  `(supervise-with (fn [] true) ~@body))

(defmacro supervise-with [check & body]
  `(forever-with ~check
    (try
      ~@body
      (catch Exception e#
        (warn e# "supervised function has died, restarting")))))

;; (defn random-string [bits]
;;   (.toString (java.math.BigInteger. bits (java.security.SecureRandom.)) 32))

(def +charset-utf8+ (.get (java.nio.charset.Charset/availableCharsets) "UTF-8"))

(defmacro str-to-json [s]
  `(json/read-str ~s :key-fn keyword))

(def json-to-str json/write-str)

(defn bytes-to-str [bytes]
  (String. bytes +charset-utf8+))

(defn str-to-bytes [s]
  (.getBytes s +charset-utf8+))

(defn bytes-to-json [bytes]
  (str-to-json (bytes-to-str bytes)))

(defn json-to-bytes [data]
  (.getBytes (json-to-str data) +charset-utf8+))

(defn hexstr-to-bytes [s]
  (org.apache.commons.codec.binary.Hex/decodeHex (.toCharArray (.substring s 2))))

(defn bytes-to-hexstr [b]
  (let [buffer (byte-array (.remaining b))]
    (.get b buffer)
    (str "0x" (String. (org.apache.commons.codec.binary.Hex/encodeHex buffer)))))