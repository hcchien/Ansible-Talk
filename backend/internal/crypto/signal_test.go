package crypto

import (
	"testing"
)

func TestGenerateRegistrationID(t *testing.T) {
	// Test that registration ID is generated within valid range
	for i := 0; i < 100; i++ {
		id, err := GenerateRegistrationID()
		if err != nil {
			t.Fatalf("Failed to generate registration ID: %v", err)
		}

		// Registration ID should be 14 bits (0-16383)
		if id < 0 || id > 16383 {
			t.Errorf("Registration ID %d is out of range (0-16383)", id)
		}
	}
}

func TestGenerateRegistrationID_Uniqueness(t *testing.T) {
	// Test that multiple calls generate different IDs (with high probability)
	ids := make(map[int]bool)
	duplicates := 0

	for i := 0; i < 1000; i++ {
		id, err := GenerateRegistrationID()
		if err != nil {
			t.Fatalf("Failed to generate registration ID: %v", err)
		}

		if ids[id] {
			duplicates++
		}
		ids[id] = true
	}

	// With 16384 possible values and 1000 samples, we expect very few duplicates
	// Allow up to 10% duplicates due to birthday paradox
	if duplicates > 100 {
		t.Errorf("Too many duplicate registration IDs: %d out of 1000", duplicates)
	}
}

func TestKeyBundle_Structure(t *testing.T) {
	// Test that KeyBundle struct has correct fields
	bundle := KeyBundle{
		RegistrationID: 12345,
		IdentityKey:    []byte("test-identity-key"),
		SignedPreKey: SignedPreKey{
			KeyID:     1,
			PublicKey: []byte("test-signed-prekey"),
			Signature: []byte("test-signature"),
		},
		PreKey: &PreKey{
			KeyID:     0,
			PublicKey: []byte("test-prekey"),
		},
	}

	if bundle.RegistrationID != 12345 {
		t.Errorf("Expected registration ID 12345, got %d", bundle.RegistrationID)
	}

	if bundle.SignedPreKey.KeyID != 1 {
		t.Errorf("Expected signed pre-key ID 1, got %d", bundle.SignedPreKey.KeyID)
	}

	if bundle.PreKey == nil {
		t.Error("Expected pre-key to be non-nil")
	}

	if bundle.PreKey.KeyID != 0 {
		t.Errorf("Expected pre-key ID 0, got %d", bundle.PreKey.KeyID)
	}
}

func TestKeyBundle_OptionalPreKey(t *testing.T) {
	// Test that PreKey can be nil (one-time pre-keys can be exhausted)
	bundle := KeyBundle{
		RegistrationID: 12345,
		IdentityKey:    []byte("test-identity-key"),
		SignedPreKey: SignedPreKey{
			KeyID:     1,
			PublicKey: []byte("test-signed-prekey"),
			Signature: []byte("test-signature"),
		},
		PreKey: nil,
	}

	if bundle.PreKey != nil {
		t.Error("Expected pre-key to be nil")
	}
}

func TestSignedPreKey_Structure(t *testing.T) {
	spk := SignedPreKey{
		KeyID:     42,
		PublicKey: []byte("public-key-bytes"),
		Signature: []byte("signature-bytes"),
	}

	if spk.KeyID != 42 {
		t.Errorf("Expected key ID 42, got %d", spk.KeyID)
	}

	if string(spk.PublicKey) != "public-key-bytes" {
		t.Errorf("Unexpected public key: %s", string(spk.PublicKey))
	}

	if string(spk.Signature) != "signature-bytes" {
		t.Errorf("Unexpected signature: %s", string(spk.Signature))
	}
}

func TestPreKey_Structure(t *testing.T) {
	pk := PreKey{
		KeyID:     100,
		PublicKey: []byte("prekey-public"),
	}

	if pk.KeyID != 100 {
		t.Errorf("Expected key ID 100, got %d", pk.KeyID)
	}

	if string(pk.PublicKey) != "prekey-public" {
		t.Errorf("Unexpected public key: %s", string(pk.PublicKey))
	}
}

func TestRegisterKeysRequest_Structure(t *testing.T) {
	req := RegisterKeysRequest{
		DeviceID:       1,
		RegistrationID: 12345,
		IdentityKey:    []byte("identity-key"),
		SignedPreKey: SignedPreKey{
			KeyID:     0,
			PublicKey: []byte("signed-prekey"),
			Signature: []byte("signature"),
		},
		PreKeys: []PreKey{
			{KeyID: 0, PublicKey: []byte("prekey-0")},
			{KeyID: 1, PublicKey: []byte("prekey-1")},
			{KeyID: 2, PublicKey: []byte("prekey-2")},
		},
	}

	if req.DeviceID != 1 {
		t.Errorf("Expected device ID 1, got %d", req.DeviceID)
	}

	if len(req.PreKeys) != 3 {
		t.Errorf("Expected 3 pre-keys, got %d", len(req.PreKeys))
	}

	for i, pk := range req.PreKeys {
		if pk.KeyID != i {
			t.Errorf("Expected pre-key ID %d, got %d", i, pk.KeyID)
		}
	}
}
