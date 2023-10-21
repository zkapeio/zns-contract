// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.4;

import "./PriceOracle.sol";
import "./BaseRegistrarImplementation.sol";
import "./StringUtils.sol";
import "./resolvers/Resolver.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC165Upgradeable as IERC165} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import {IERC721Upgradeable as IERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "./StablePriceOracle.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ZNSRegistrarController is Ownable {
    using StringUtils for *;

    struct Vars {
        bytes32 leaf;
        bytes32 commitment;
        uint cost;
        bytes32 label;
        uint256 tokenId;
        uint expires;
        uint nftValue;
        address owner;
        address resolver;
        address addr;
        uint nameLen;
        IERC721 nft;
        bytes32 nodehash;
        uint duration;
        string name;
    }

    bytes32 internal constant _signMin_ = "signMin";
    bytes32 internal constant _airDropAcc_ = "airDropAcc";

    uint256 private constant YEAR = 365 days;
    uint256 private constant MONTH = 30 days;

    uint public MIN_REGISTRATION_DURATION; //= 28 days;

    bytes4 private constant INTERFACE_META_ID =
        bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 private constant COMMITMENT_CONTROLLER_ID =
        bytes4(
            keccak256("rentPrice(string,uint256)") ^
                keccak256("available(string)") ^
                keccak256("makeCommitment(string,address,bytes32)") ^
                keccak256("commit(bytes32)") ^
                keccak256("register(string,address,uint256,bytes32)") ^
                keccak256("renew(string,uint256)")
        );

    bytes4 private constant COMMITMENT_WITH_CONFIG_CONTROLLER_ID =
        bytes4(
            keccak256(
                "registerWithConfig(string,address,uint256,bytes32,address,address)"
            ) ^
                keccak256(
                    "makeCommitmentWithConfig(string,address,bytes32,address,address)"
                )
        );

    BaseRegistrarImplementation public base;
    PriceOracle public prices;
    uint256 public minCommitmentAge; //60 s
    uint256 public maxCommitmentAge; //24 hour
    uint public wlBegin;
    uint public wlEnd;
    mapping(bytes32 => uint) public commitments;

    mapping(address => mapping(uint => bool)) public isWlReged; // address =>3 or 4chart =>reged

    mapping(string => bool) public reserves;
    mapping(address => bool) public reserveAdm;
    address gov; //ethTo
    bool public registerIsActive = false;

    mapping(uint => uint) public durationDiscount; //1 90%, 2 70%, 3 50%
    mapping(address => uint) public freeRegister;

    mapping(bytes32 => uint) public conf;
    bytes32 public wlMerkleRoot;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint cost,
        uint expires
    );
    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint cost,
        uint expires
    );
    event NewPriceOracle(address indexed oracle);

    function __ZNSRegistrarController_i(
        BaseRegistrarImplementation _base,
        PriceOracle _prices,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge,
        bytes32 _wlMerkleRoot
    ) public initializer {
        __Ownable_init();
        MIN_REGISTRATION_DURATION = 28 days;
        base = _base;
        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        wlMerkleRoot = _wlMerkleRoot;
    }

    function costEth(
        string memory name,
        uint duration
    ) public view returns (uint) {
        return rentPrice(name, duration);
    }

    function passToEth() public view returns (uint) {
        return prices.attoUSDToWei(1798 * 1e17);
    }

    function rentPrice(
        string memory name,
        uint duration
    ) public view returns (uint) {
        bytes32 hash = keccak256(bytes(name));
        uint cost = prices.price(
            name,
            base.nameExpires(uint256(hash)),
            duration
        );
        if (
            name.strlen() >= 5 &&
            duration <= 3 * MONTH &&
            freeRegister[msg.sender] < 1
        ) {
            cost = 0;
        }
        if (duration >= 3 * YEAR && duration < 5 * YEAR) {
            cost = (cost * durationDiscount[3]) / 10;
        } else if (duration >= 5 * YEAR && duration < 10 * YEAR) {
            cost = (cost * durationDiscount[5]) / 10;
        } else if (duration >= 10 * YEAR) {
            cost = (cost * durationDiscount[10]) / 10;
        }
        return cost;
    }

    function check(string memory name, bool isNum) public pure returns (bool) {
        bytes memory namebytes = bytes(name);
        for (uint256 i; i < namebytes.length; i++) {
            if (!exists(bytes1(namebytes[i]), isNum)) return false;
        }
        return true;
    }

    function exists(bytes1 char, bool isNum) public pure returns (bool) {
        bytes memory charsets;
        if (isNum) charsets = bytes("0123456789");
        else charsets = bytes("abcdefghijklmnopqrstuvwxyz-0123456789");
        for (uint256 i = 0; i < charsets.length; i++) {
            if (bytes1(charsets[i]) == char) {
                return true;
            }
        }
        return false;
    }

    function valid(string memory name, bool isNum) public pure returns (bool) {
        // check unicode rune count, if rune count is >=3, byte length must be >=3. <=63
        if (name.strlen() < 3 || name.strlen() > 63) {
            return false;
        }
        if (!check(name, isNum)) return false;
        bytes memory nb = bytes(name);
        if (nb[0] == 0x2d || nb[nb.length - 1] == 0x2d) return false;
        for (uint256 i; i < nb.length - 2; i++) {
            if ((bytes1(nb[i]) == 0x2d) && (bytes1(nb[i + 1]) == 0x2d)) {
                //--
                return false;
            }
        }
        return true;
    }

    function setReserves(
        string[] calldata names,
        bool[] calldata isReserves
    ) public onlyOwner {
        require(names.length == isReserves.length, "len not match");
        for (uint i = 0; i < names.length; i++) {
            reserves[names[i]] = isReserves[i];
        }
    }

    function setDurationDiscount(
        uint[] calldata durations,
        uint[] calldata discounts
    ) public onlyOwner {
        require(durations.length == discounts.length, "len not match");
        for (uint i = 0; i < durations.length; i++) {
            durationDiscount[durations[i]] = discounts[i];
        }
    }

    function setReserveAdm(address acct, bool isAdm) public onlyOwner {
        reserveAdm[acct] = isAdm;
    }

    function setGov(address _gov) public onlyOwner {
        gov = _gov;
    }

    function setConf(bytes32 key, uint value) public onlyOwner {
        conf[key] = value;
    }

    function setDur(uint _day) public onlyOwner {
        MIN_REGISTRATION_DURATION = 86400 * _day;
    }

    function flipRegisterState() public onlyOwner {
        registerIsActive = !registerIsActive;
    }

    function setWlReged(
        address _address,
        uint _len,
        bool _bool
    ) public onlyOwner {
        isWlReged[_address][_len] = _bool;
    }

    function setTime(uint _wlBegin, uint _wlEnd) public onlyOwner {
        wlBegin = _wlBegin;
        wlEnd = _wlEnd;
    }

    function updateWlMerkleRoot(bytes32 merkleRoot_) public onlyOwner {
        wlMerkleRoot = merkleRoot_;
    }

    function available(
        string memory name,
        bool isNum
    ) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name, isNum) && base.available(uint256(label));
    }

    function wlReged(address _address, uint _len) public view returns (bool) {
        return isWlReged[_address][_len];
    }

    function isWhiteListed(
        address _address,
        uint namelen,
        uint duration,
        bytes32[] calldata _merkleProof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_address, namelen, duration));
        return MerkleProofUpgradeable.verify(_merkleProof, wlMerkleRoot, leaf);
    }

    function isLimit(
        string memory name,
        address acct
    ) public view returns (bool) {
        if (reserveAdm[acct]) return false;
        if (reserves[name]) return true;
        return false;
    }

    /*function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret
    ) public pure returns (bytes32) {
        return
            makeCommitmentWithConfig(
                name,
                owner,
                secret,
                address(0),
                address(0)
            );
    }

    function makeCommitmentWithConfig(
        string memory name,
        address owner,
        bytes32 secret,
        address resolver,
        address addr
    ) public pure returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        if (resolver == address(0) && addr == address(0)) {
            return keccak256(abi.encodePacked(label, owner, secret));
        }
        require(resolver != address(0));
        return
            keccak256(abi.encodePacked(label, owner, resolver, addr, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < block.timestamp);
        commitments[commitment] = block.timestamp;
    }*/

    function wlRegister(
        string calldata name,
        address owner,
        uint duration,
        /*bytes32 secret,*/
        bytes32[] calldata _wlmerkleProof
    ) external payable {
        Vars memory vars;
        vars.leaf = keccak256(abi.encodePacked(msg.sender));
        uint nameLen = name.strlen();
        require(!isLimit(name, msg.sender), "name reserved"); //reserve
        require(available(name, false), "name unavailable");
        require(registerIsActive, "register must be active");

        require(
            isWhiteListed(msg.sender, nameLen, duration, _wlmerkleProof),
            "Invalid Proof."
        );
        require(!isWlReged[msg.sender][nameLen], "Address already registered");
        isWlReged[msg.sender][nameLen] = true;
        vars.owner = owner;
        // vars.commitment = makeCommitment(name, owner, secret);
        // vars.cost = _consumeCommitment(
        //     name,
        //     duration,
        //     vars.commitment,
        //     1e18,
        //     true
        // );
        vars.cost = getCost(name, duration, 1e18, true);
        vars.label = keccak256(bytes(name));
        vars.tokenId = uint256(vars.label);

        vars.name = name;
        vars.duration = duration;
        RegisterInter(vars);
    }

    function RegisterWithConfig(
        string calldata name,
        uint duration,
        /*bytes32 secret,*/
        address[] calldata ora
    ) external payable {
        // ora:address owner,address resolver, address addr
        require(available(name, false), "name unavailable");
        require(!isLimit(name, msg.sender), "name reserved"); //reserve
        require(registerIsActive, "register must be active");

        Vars memory vars;
        vars.owner = ora[0];
        vars.resolver = ora[1];
        vars.addr = ora[2];
        // vars.commitment = makeCommitmentWithConfig(
        //     name,
        //     vars.owner,
        //     secret,
        //     vars.resolver,
        //     vars.addr
        // );
        // vars.cost = _consumeCommitment(
        //     name,
        //     duration,
        //     vars.commitment,
        //     1e18,
        //     false
        // );
        vars.cost = getCost(name, duration, 1e18, false);
        vars.label = keccak256(bytes(name));
        vars.tokenId = uint256(vars.label);

        vars.name = name;
        vars.duration = duration;
        RegisterInter(vars);
        if (vars.cost == 0) {
            freeRegister[msg.sender]++;
        }
        // Refund any extra payment
        if (msg.value > vars.cost) {
            (bool os, ) = payable(msg.sender).call{
                value: msg.value - vars.cost
            }("");
            require(os);
        }
    }

    function RegisterInter(Vars memory vars) internal {
        if (vars.resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            vars.expires = base.registerWithName(
                vars.tokenId,
                address(this),
                vars.duration,
                vars.name
            );

            // The nodehash of this label
            bytes32 nodehash = keccak256(
                abi.encodePacked(base.baseNode(), vars.label)
            );

            // Set the resolver
            base.zns().setResolver(nodehash, vars.resolver);

            // Configure the resolver
            if (vars.addr != address(0)) {
                Resolver(vars.resolver).setAddr(nodehash, vars.addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(vars.tokenId, vars.owner);
            base.transferFrom(address(this), vars.owner, vars.tokenId);
        } else {
            require(vars.addr == address(0));
            vars.expires = base.registerWithName(
                vars.tokenId,
                vars.owner,
                vars.duration,
                vars.name
            );
        }
        emit NameRegistered(
            vars.name,
            vars.label,
            vars.owner,
            vars.cost,
            vars.expires
        );
    }

    function renew(string calldata name, uint duration) external payable {
        uint cost = rentPrice(name, duration);

        require(duration >= YEAR, "Renew duration must be >= 1 year");

        require(msg.value >= cost);
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);
        if (msg.value > cost) {
            (bool os, ) = payable(msg.sender).call{value: msg.value - cost}("");
            require(os);
        }
        emit NameRenewed(name, label, cost, expires);
    }

    function setPriceOracle(PriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function setBase(BaseRegistrarImplementation _base) public onlyOwner {
        base = _base;
    }

    function setCommitmentAges(
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge
    ) public onlyOwner {
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        (bool os, ) = payable(msg.sender).call{value: balance}("");
        require(os);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == INTERFACE_META_ID ||
            interfaceID == COMMITMENT_CONTROLLER_ID ||
            interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID;
    }

    function getCost(
        string memory name,
        uint duration,
        uint rate,
        bool rs
    ) internal returns (uint256) {
        uint cost = (costEth(name, duration) * rate) / 1e18;
        if (rs) {
            cost = 0;
        } else {
            require(duration >= MIN_REGISTRATION_DURATION);
            require(msg.value >= cost, "Ether value sent is not correct");
        }
        return cost;
    }

    /*function _consumeCommitment(
        string memory name,
        uint duration,
        bytes32 commitment,
        uint rate,
        bool rs
    ) internal returns (uint256) {
        // Require a valid commitment
        require(commitments[commitment] + minCommitmentAge <= block.timestamp);

        // If the commitment is too old, or the name is registered, stop
        require(commitments[commitment] + maxCommitmentAge > block.timestamp);

        delete (commitments[commitment]);

        uint cost = (costEth(name, duration) * rate) / 1e18;

        if (rs) {
            cost = 0;
        } else {
            require(duration >= MIN_REGISTRATION_DURATION);
            require(msg.value >= cost, "Ether value sent is not correct");
        }

        return cost;
    }*/

    //----------------------------------------
    //public register  owner
    function batchRegister(
        string[] memory names,
        uint[] calldata durations,
        address[] calldata owners,
        address resolver
    ) public {
        // ora:address owner,address resolver, address addr
        require(conf[_airDropAcc_] == uint(uint160(msg.sender)), "E");
        require(
            (names.length == durations.length) &&
                (names.length == owners.length),
            "len!"
        );
        Vars memory vars;
        vars.resolver = resolver;
        for (uint256 i; i < names.length; i++) {
            string memory name = names[i];
            vars.owner = owners[i];
            vars.addr = owners[i];
            vars.label = keccak256(bytes(name));
            vars.tokenId = uint256(vars.label);
            vars.name = name;
            vars.duration = durations[i];
            RegisterInter(vars);
        }
    }
}
