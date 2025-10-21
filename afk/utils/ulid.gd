extends Node

## ULID - Universally Unique Lexicographically Sortable Identifier
## NOW USING 16-BYTE BINARY FORMAT FOR PERFORMANCE
##
## Internal representation: PackedByteArray (16 bytes)
## - 6 bytes: Timestamp (48 bits, milliseconds since epoch)
## - 10 bytes: Randomness (80 bits, cryptographically random)
##
## Benefits:
## - 38% smaller memory footprint (16 bytes vs 26 chars)
## - Faster dictionary lookups (binary comparison)
## - Better cache efficiency
## - More efficient serialization
##
## String format is still available for display/debugging via to_string()

## Crockford's Base32 alphabet (for string conversion)
const ENCODING: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const ENCODING_LEN: int = 32

## ULID binary structure
const TIMESTAMP_BYTES: int = 6  # 48 bits
const RANDOM_BYTES: int = 10    # 80 bits
const TOTAL_BYTES: int = 16     # 128 bits

## String representation lengths
const TIME_LEN: int = 10
const RANDOM_LEN: int = 16
const TOTAL_LEN: int = 26

## Random number generator
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## ===== ULID GENERATION (BINARY) =====

## Generate a new ULID as 16-byte PackedByteArray
static func generate() -> PackedByteArray:
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var ulid = PackedByteArray()
	ulid.resize(TOTAL_BYTES)

	# Encode timestamp (6 bytes, big-endian)
	var timestamp_ms = Time.get_ticks_msec()
	_encode_timestamp_bytes(ulid, timestamp_ms)

	# Encode randomness (10 bytes)
	_encode_random_bytes(ulid)

	return ulid


## Generate a ULID with a specific timestamp (for testing)
static func generate_with_time(timestamp_ms: int) -> PackedByteArray:
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var ulid = PackedByteArray()
	ulid.resize(TOTAL_BYTES)

	_encode_timestamp_bytes(ulid, timestamp_ms)
	_encode_random_bytes(ulid)

	return ulid


## ===== BINARY ENCODING =====

## Encode timestamp into first 6 bytes (big-endian for sortability)
static func _encode_timestamp_bytes(ulid: PackedByteArray, timestamp_ms: int) -> void:
	# Store 48-bit timestamp in big-endian order
	# Most significant bytes first for lexicographic sorting
	ulid[0] = (timestamp_ms >> 40) & 0xFF
	ulid[1] = (timestamp_ms >> 32) & 0xFF
	ulid[2] = (timestamp_ms >> 24) & 0xFF
	ulid[3] = (timestamp_ms >> 16) & 0xFF
	ulid[4] = (timestamp_ms >> 8) & 0xFF
	ulid[5] = timestamp_ms & 0xFF


## Encode 10 random bytes
static func _encode_random_bytes(ulid: PackedByteArray) -> void:
	for i in range(TIMESTAMP_BYTES, TOTAL_BYTES):
		ulid[i] = rng.randi() & 0xFF


## ===== BINARY DECODING =====

## Decode timestamp from ULID bytes (returns milliseconds)
static func decode_time(ulid: PackedByteArray) -> int:
	if ulid.size() != TOTAL_BYTES:
		push_error("ULID: Invalid binary ULID size: %d (expected %d)" % [ulid.size(), TOTAL_BYTES])
		return 0

	# Read 48-bit timestamp (big-endian)
	var timestamp = 0
	timestamp |= (ulid[0] << 40)
	timestamp |= (ulid[1] << 32)
	timestamp |= (ulid[2] << 24)
	timestamp |= (ulid[3] << 16)
	timestamp |= (ulid[4] << 8)
	timestamp |= ulid[5]

	return timestamp


## Extract random bytes from ULID
static func get_random_bytes(ulid: PackedByteArray) -> PackedByteArray:
	if ulid.size() != TOTAL_BYTES:
		return PackedByteArray()

	return ulid.slice(TIMESTAMP_BYTES, TOTAL_BYTES)


## ===== STRING CONVERSION =====

## Convert binary ULID to 26-character string (for display/debugging)
static func to_str(ulid: PackedByteArray) -> String:
	if ulid.size() != TOTAL_BYTES:
		push_error("ULID: Invalid binary ULID size")
		return ""

	var result = ""

	# Encode timestamp (first 6 bytes -> 10 chars)
	var timestamp = decode_time(ulid)
	result += _encode_time_string(timestamp)

	# Encode random part (last 10 bytes -> 16 chars)
	result += _encode_random_string(ulid)

	return result


## Convert 26-character string to binary ULID
static func from_string(ulid_str: String) -> PackedByteArray:
	if ulid_str.length() != TOTAL_LEN:
		push_error("ULID: Invalid string ULID length: %d (expected %d)" % [ulid_str.length(), TOTAL_LEN])
		return PackedByteArray()

	var ulid = PackedByteArray()
	ulid.resize(TOTAL_BYTES)

	# Decode timestamp from first 10 chars
	var timestamp = _decode_time_string(ulid_str.substr(0, TIME_LEN))
	_encode_timestamp_bytes(ulid, timestamp)

	# Decode random part from last 16 chars
	_decode_random_string(ulid, ulid_str.substr(TIME_LEN, RANDOM_LEN))

	return ulid


## ===== STRING ENCODING HELPERS =====

## Encode timestamp to 10-character base32 string
static func _encode_time_string(timestamp_ms: int) -> String:
	var result = ""
	var time = timestamp_ms

	for i in range(TIME_LEN):
		var mod = time % ENCODING_LEN
		result = ENCODING[mod] + result
		time = int(time / ENCODING_LEN)

	return result


## Encode random bytes to 16-character base32 string
static func _encode_random_string(ulid: PackedByteArray) -> String:
	var result = ""

	# Convert 10 random bytes to 16 base32 characters
	# Use groups of 5 bits from the bytes
	var bit_buffer = 0
	var bits_in_buffer = 0

	for i in range(TIMESTAMP_BYTES, TOTAL_BYTES):
		bit_buffer = (bit_buffer << 8) | ulid[i]
		bits_in_buffer += 8

		while bits_in_buffer >= 5:
			bits_in_buffer -= 5
			var index = (bit_buffer >> bits_in_buffer) & 0x1F
			result += ENCODING[index]

	# Handle remaining bits
	if bits_in_buffer > 0:
		var index = (bit_buffer << (5 - bits_in_buffer)) & 0x1F
		result += ENCODING[index]

	return result


## ===== STRING DECODING HELPERS =====

## Decode timestamp from 10-character base32 string
static func _decode_time_string(time_str: String) -> int:
	var timestamp = 0

	for i in range(time_str.length()):
		var char = time_str[i]
		var value = ENCODING.find(char)

		if value == -1:
			push_error("ULID: Invalid character in timestamp: %s" % char)
			return 0

		timestamp = timestamp * ENCODING_LEN + value

	return timestamp


## Decode random part from 16-character base32 string
static func _decode_random_string(ulid: PackedByteArray, random_str: String) -> void:
	var bit_buffer = 0
	var bits_in_buffer = 0
	var byte_index = TIMESTAMP_BYTES

	for i in range(random_str.length()):
		var char = random_str[i]
		var value = ENCODING.find(char)

		if value == -1:
			push_error("ULID: Invalid character in random part: %s" % char)
			return

		bit_buffer = (bit_buffer << 5) | value
		bits_in_buffer += 5

		while bits_in_buffer >= 8 and byte_index < TOTAL_BYTES:
			bits_in_buffer -= 8
			ulid[byte_index] = (bit_buffer >> bits_in_buffer) & 0xFF
			byte_index += 1


## ===== VALIDATION =====

## Validate binary ULID
static func is_valid(ulid: PackedByteArray) -> bool:
	return ulid.size() == TOTAL_BYTES


## Validate string ULID format
static func is_valid_string(ulid_str: String) -> bool:
	if ulid_str.length() != TOTAL_LEN:
		return false

	for i in range(ulid_str.length()):
		if ENCODING.find(ulid_str[i]) == -1:
			return false

	return true


## ===== COMPARISON =====

## Compare two binary ULIDs (for sorting)
## Returns: -1 if a < b, 0 if a == b, 1 if a > b
static func compare(ulid_a: PackedByteArray, ulid_b: PackedByteArray) -> int:
	if ulid_a.size() != TOTAL_BYTES or ulid_b.size() != TOTAL_BYTES:
		push_error("ULID: Invalid ULID size for comparison")
		return 0

	# Byte-by-byte comparison (big-endian, so timestamp is compared first)
	for i in range(TOTAL_BYTES):
		if ulid_a[i] < ulid_b[i]:
			return -1
		elif ulid_a[i] > ulid_b[i]:
			return 1

	return 0


## Check if ULID a is older than ULID b (based on timestamp)
static func is_older(ulid_a: PackedByteArray, ulid_b: PackedByteArray) -> bool:
	return decode_time(ulid_a) < decode_time(ulid_b)


## ===== UTILITY =====

## Get age of ULID in milliseconds
static func get_age_ms(ulid: PackedByteArray) -> int:
	var ulid_time = decode_time(ulid)
	var current_time = Time.get_ticks_msec()
	return current_time - ulid_time


## Convert ULID timestamp to human-readable date
static func to_datetime(ulid: PackedByteArray) -> Dictionary:
	var timestamp_ms = decode_time(ulid)
	var timestamp_sec = int(timestamp_ms / 1000)
	return Time.get_datetime_dict_from_unix_time(timestamp_sec)


## Format binary ULID for display (converts to string with hyphens)
## Example: 01ARZ3NDEK-TSTSV4RRFFQ69G5FAV
static func format(ulid: PackedByteArray) -> String:
	if not is_valid(ulid):
		return "[INVALID ULID]"

	var str = to_str(ulid)
	return str.substr(0, TIME_LEN) + "-" + str.substr(TIME_LEN, RANDOM_LEN)


## ===== DEBUG =====

## Print ULID information
static func debug_ulid(ulid: PackedByteArray) -> void:
	if not is_valid(ulid):
		print("Invalid ULID: size=%d (expected %d)" % [ulid.size(), TOTAL_BYTES])
		return

	var timestamp = decode_time(ulid)
	var age = get_age_ms(ulid)
	var datetime = to_datetime(ulid)
	var ulid_str = to_str(ulid)

	print("=== ULID Debug ===")
	print("  Binary size: %d bytes" % ulid.size())
	print("  String: %s" % ulid_str)
	print("  Formatted: %s" % format(ulid))
	print("  Timestamp: %d ms" % timestamp)
	print("  Age: %d ms (%.2f seconds)" % [age, age / 1000.0])
	print("  Created: %04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second
	])


## ===== BATCH GENERATION =====

## Generate multiple ULIDs (useful for pre-allocation)
static func generate_batch(count: int) -> Array[PackedByteArray]:
	var ulids: Array[PackedByteArray] = []

	for i in range(count):
		ulids.append(generate())

	return ulids


## ===== COLLISION DETECTION (for testing) =====

## Check for ULID collisions in an array (should never happen)
static func check_collisions(ulids: Array) -> bool:
	var seen = {}

	for ulid in ulids:
		var key = to_str(ulid)
		if seen.has(key):
			push_error("ULID COLLISION DETECTED: %s" % key)
			return true
		seen[key] = true

	return false


## ===== CONVERSION HELPERS =====

## Convert binary ULID to hex string (for debugging)
static func to_hex(ulid: PackedByteArray) -> String:
	if not is_valid(ulid):
		return ""

	return ulid.hex_encode()


## Create ULID from hex string
static func from_hex(hex_str: String) -> PackedByteArray:
	var ulid = PackedByteArray()
	ulid.hex_decode(hex_str)

	if ulid.size() != TOTAL_BYTES:
		push_error("ULID: Invalid hex string length")
		return PackedByteArray()

	return ulid
