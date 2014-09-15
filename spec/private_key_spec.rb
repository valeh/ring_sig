require 'spec_helper'

describe RingSig::PrivateKey do
  hasher = RingSig::Hasher::Secp256k1_Sha256
  key = RingSig::PrivateKey.new(1, hasher)
  key_hex = '0000000000000000000000000000000000000000000000000000000000000001'
  group = ECDSA::Group::Secp256k1
  message = 'a'
  # The public keys from the coinbase transactions in the first three bitcoin blocks:
  foreign_keys = %w{
      04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f
      0496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858ee
      047211a824f55b505228e4c3d5194c1fcfaa15a456abdf37f9b9d97a4040afc073dee6c89064984f03385237d92167c13e236446b417ab79a0fcae412ae3316b77
    }.map {|s| RingSig::PublicKey.from_hex(s, hasher) }

  it 'raises ArgumentError if value is too small' do
    expect { RingSig::PrivateKey.new(0, hasher) }.to raise_error(ArgumentError)
  end

  it 'raises ArgumentError if value is too large' do
    expect { RingSig::PrivateKey.new(group.order, hasher) }.to raise_error(ArgumentError)
  end

  describe '#key_image' do
    it 'computes correctly' do
      expect(key.key_image.x).to eq(19808304348355547845585283516832906889081321816618757912787193259813413622341)
      expect(key.key_image.y).to eq(6456680440731674563715553325029463353567815591885844101408227481418612066782)
    end
  end

  describe '#public_key' do
    it 'computes correctly' do
      expect(key.public_key.to_hex).to eq("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
    end
  end

  describe '#point' do
    it 'equals the public key point' do
      expect(key.point).to eq(key.public_key.point)
    end
  end

  describe '#to_hex' do
    it 'converts to hex' do
      expect(key.to_hex).to eq key_hex
    end
  end

  describe '#from_hex' do
    it 'converts from hex' do
      expect(RingSig::PrivateKey.from_hex(key_hex, hasher)).to eq key
    end
  end

  describe '#to_octet' do
    it 'converts to octet' do
      expect(key.to_octet).to eq [key_hex].pack('H*')
    end
  end

  describe '#from_octet' do
    it 'converts from octet' do
      expect(RingSig::PrivateKey.from_octet([key_hex].pack('H*'), hasher)).to eq key
    end
  end

  describe '==' do
    it 'returns true when keys are the same' do
      expect(key).to eq key
      expect(RingSig::PrivateKey.new(key.value, hasher) == key).to eq true
    end

    it 'returns false when keys are different' do
      expect(RingSig::PrivateKey.new(2, hasher) == key).to eq false
    end
  end

  describe '#sign' do
    sig, public_keys = key.sign(message, foreign_keys)

    it 'signs and verifies' do
      expect(sig.to_hex).to eq '3082013d0421022bcb1a5b3c70421bfac818f6bd13289a5c9a3cfb42d3b81f023a0276974c924530818a02200b084320e064c99a4c25122fbbae407f9a5b2b4f063d2276500e051641a04f79022100b6c3d4ec0f42acf78ffd5697da7145cf1f274410ccbdb02bae3da79c25dd324c02210086861195f0eecb9948bf421ca5ce4c0f4e5838e7fe0735d2afd40bc5c10c849102200c84c1450e3a0b092f4449204b531a02d1f9f7eafef6d34bbe599d944a85eba930818a022100cb8f91859d1cd0308ecd3a278d0334da2e97a7dc54d36bbbb266cd2187c78bc4022100a81cff48a1e5ca431c30e3e658d22447cf808cd414cccdb84d43bb72a91c3add02201c9ef437f57532ab0e916536709aacde09f2243297e1d6e3992385cc603d41540220690ddd89d38482bb42e59ee6f2279c8f35a8211300e13939aed00e91bb3d9661'

      expected_public_keys = [2, 1, 0, 3].map{|i| ([key] + foreign_keys)[i].public_key}
      expect(public_keys).to eq expected_public_keys

      expect(sig.verify(message, public_keys)).to be true
      expect(sig.verify(message + '0', public_keys)).to be false
      expect(sig.verify(message, public_keys.reverse)).to be false
    end

    it 'has the same key_image for different foreign keys' do
      other_sig, other_public_keys = key.sign(message, foreign_keys[0..1])

      expect(sig.to_hex).not_to eq(other_sig.to_hex)
      expect(sig.key_image).to eq(other_sig.key_image)
    end

    it 'signs and verifies with no foreign keys' do
      sig, public_keys = key.sign(message, [])

      expect(sig.to_hex).to eq '306c0421022bcb1a5b3c70421bfac818f6bd13289a5c9a3cfb42d3b81f023a0276974c9245302202202a2c0676992db106d54b0d2834c53b95b55d524c7449b55202f3ccb465ce73873023022100a1638b0f03ef1f29b9822cff583df944793a558fe089b669af73006d21f9183d'
      expect(public_keys).to eq [key.public_key]

      expect(sig.verify(message, public_keys)).to be true
    end
  end

  context 'alternate hasher' do
    before(:all) do
      @key = RingSig::PrivateKey.new(1, RingSig::Hasher::Secp160k1_Ripemd160)
      @foreign_keys = [
          RingSig::PrivateKey.new(2, RingSig::Hasher::Secp160k1_Ripemd160).public_key,
          RingSig::PrivateKey.new(3, RingSig::Hasher::Secp160k1_Ripemd160).public_key,
        ]
    end

    describe '#sign' do
      it 'signs and verifies' do
        sig, public_keys = @key.sign(message, @foreign_keys)

        expect(sig.to_hex).to eq '3081a004150335d6eb01d7c658c2aae34e1e910e1b44c993069d30430214685baa33eacec37ff3530d710ca852731e1ac7b0021500881bf1e9c67d05c7a8a6ef93552a7852466034360214211b72b5e3a934d0e096441c5208b4322a83b7a130420214098d90e6e0a5e08186815be4a20a41480d55d7c202141cd9f8cc0df48519ecd6ad6e354ca634c8b604c2021415019f51cc2480ef6148dcd35a4be28037bf8899'

        expected_public_keys = [2, 1, 0].map{|i| ([@key] + @foreign_keys)[i].public_key}
        expect(public_keys).to eq expected_public_keys

        expect(sig.verify(message, public_keys)).to be true
      end
    end
  end
end
