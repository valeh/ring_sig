module RingSig
  # A customized hasher specifically for Ring Signatures.
  class Hasher
    # @return [ECDSA::Group]
    attr_reader :group

    # @return [#digest]
    attr_reader :algorithm

    # Creates a new instance of {Hasher}.
    #
    # @note The byte-length of the group's order and the digest method must
    #   match, or else signatures generated from this hasher will leak the
    #   position of the true signer.
    #
    # @param group [ECDSA::Group]
    # @param algorithm [#digest]
    def initialize(group, algorithm)
      @group = group
      @algorithm = algorithm

      algorithm_byte_length = algorithm.digest('a').size
      if group.byte_length != algorithm_byte_length
        raise ArgumentError, "Group's byte length (#{group.byte_length}), does not match hash algorithm's byte length (#{algorithm_byte_length})"
      end

      digest_max = 2 ** (algorithm_byte_length * 8) - 1
      if digest_max < group.order
        raise ArgumentError, "Invalid ECDSA group. Group's order must be less than the hash algorithm's maximum value"
      end

      @hash_cieling = digest_max - digest_max % group.order
    end

    # Uniformly hashes a string to a number between 0 and the group's order.
    #
    # @param s (String) The string to be hashed.
    # @return (Integer) A number between 0 and the group's order.
    def hash_string(s)
      n = nil
      loop do
        s = algorithm.digest(s)
        n = s.unpack('H*').first.to_i(16)
        break if n < @hash_cieling
      end
      n % group.order
    end

    # Hashes an array. Converts the Array to an OpenSSL::ASN1::Sequence der
    # string, and then hashes that string.
    #
    # @param array [Array<String,Integer,ECDSA::Point>] The array to be hashed.
    # @return [Integer] A number between 0 and the group's order.
    def hash_array(array)
      array = array.map do |e|
        case e
        when String
          OpenSSL::ASN1::UTF8String.new(e)
        when Integer
          OpenSSL::ASN1::Integer.new(e)
        when ECDSA::Point
          OpenSSL::ASN1::OctetString.new(ECDSA::Format::PointOctetString.encode(e, compression: true))
        else
          raise ArgumentError, "Unsupported type: #{p.inspect}"
        end
      end

      hash_string(OpenSSL::ASN1::Sequence.new(array).to_der)
    end

    # Hashes a point to another point.
    #
    # @param point [ECDSA::Point] The point to be hashed.
    # @return [ECDSA::Point] A new point, deterministically computed from the
    #   input point.
    def hash_point(point)
      @group.generator * hash_array(point.coords)
    end

    # Shuffles an array in a deterministic manner.
    #
    # @param array (Array) The array to be shuffled.
    # @param seed (Integer) A random seed which determines the outcome of the
    #   shuffle.
    # @return (Array) The shuffled array.
    def shuffle(array, seed)
      seed_array = [seed, 0]
      (array.size - 1).downto(1) do |i|
        r = next_rand(i + 1, seed_array)
        array[i], array[r] = array[r], array[i]
      end
      array
    end

    # @return [Boolean] true if the hashers are equal.
    def ==(other)
      group == other.group && algorithm == other.algorithm
    end

    private

    # Deterministically returns a random number between 0 and n.
    #
    # @param n (Integer) The maximum value.
    # @param seed_array (Array<Integer>) A pair `[seed, suffix]`.
    #   The suffix will be modified.
    # @return (Integer) A number between 0 and n.
    def next_rand(n, seed_array)
      loop do
        r = hash_array(seed_array)
        seed_array[1] += 1
        return r % n if r < @group.order - @group.order % n
      end
    end

    Secp256k1_Sha256 = new(ECDSA::Group::Secp256k1, OpenSSL::Digest::SHA256)
    Secp256r1_Sha256 = new(ECDSA::Group::Secp256r1, OpenSSL::Digest::SHA256)
    Secp384r1_Sha384 = new(ECDSA::Group::Secp384r1, OpenSSL::Digest::SHA384)
  end
end
