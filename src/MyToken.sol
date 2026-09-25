// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract URWA {

    string public name = "URWA-AMIOLA";
    string public symbol = "URWA";
    address public owner;
    uint256 public totalSupply;

    uint256 public constant MAX_TOKENS = 1000000000 * 10 ** 18;


    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public allowList; 
    mapping(address => uint256) public frozenTokens;
    

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Frozen(address indexed account, uint256 amount);
    event unFrozen(address indexed account, uint256 amount);
    event forcedTransferSuccess(address indexed from, address indexed to, uint256 amount, uint256 fromBalance, uint256 fromFrozen);


    //errors
    error InsufficientBalance(uint256 balance, uint256 amount);
    error InsufficientAllowance(uint256 allowance, uint256 amount);
    error ERC7943CannotSend(address account);
    error ERC7943CannotReceive(address account);
    error NotOwner();
    error NotFound();
    error ERC7943RejectTransfer(uint256 _amount, address from, address to);
    error AlreadyFrozen(address account);


    constructor () {
        owner = msg.sender;
        totalSupply = 1000000000 * 10 ** 18;
        balanceOf[msg.sender] = totalSupply;
        allowList[msg.sender] = true;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        _;
    }

    function checkGuardBalance(uint256 _senderBalance, uint256 _amount) internal pure returns (bool) {
       if(_senderBalance < _amount) {
          revert InsufficientBalance(_senderBalance, _amount);
       } 
       return true;
    }
    function getAvailableBalance(address account) internal view returns (uint256) {
        uint256 balance = balanceOf[account];
        uint256 frozen = frozenTokens[account];

        if (frozen >= balance) {
            return 0;
        }

        return balance - frozen;
    }


    function transfer(address _to, uint256 _amount) public returns (bool) {
        checkGuardBalance(getAvailableBalance(msg.sender), _amount);
        canTransfer(msg.sender, _to, _amount);
        balanceOf[msg.sender] -= _amount;
        balanceOf[_to] += _amount;
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        checkGuardBalance(getAvailableBalance(_from), _amount);
        checkGuardBalance(allowance[_from][msg.sender], _amount);
        canTransfer(_from, _to, _amount);
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        allowance[_from][msg.sender] -= _amount;
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function approve(address _spender, uint256 _amount) public {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
    }


    function canSend(address _sender) internal view returns (bool) {
        if (allowList[_sender] == false) {
            revert ERC7943CannotSend(_sender);
        }
        return true;
    }

    function canReceive(address _receiver) internal view returns (bool) {
        if (allowList[_receiver] == false) {
            revert ERC7943CannotReceive(_receiver);
        }
        return true;
    }

    function addToAllowList(address _to) public onlyOwner {
        allowList[_to] = true;
    }

    function removeFromAllowList(address _to) public onlyOwner {
        allowList[_to] = false;
    }

    function canTransfer(address _from, address _to, uint256 _amount) internal view returns (bool) {
        if (_amount > MAX_TOKENS) {
            revert ERC7943RejectTransfer(_amount, _from, _to);
        }

        return canSend(_from) && canReceive(_to);
    }

    function setFrozenTokens(address account, uint256 _amount) external onlyOwner returns (bool result) {
        if(balanceOf[account] < _amount ) {
            revert InsufficientBalance(_amount, balanceOf[account]);
        } else if (allowList[account] == true ) {
            revert NotFound();
        } 

        frozenTokens[account] = _amount;
        emit Frozen(account, _amount);
        return true;
    }   

    function unfreezeToken(address account, uint256 _amount) external onlyOwner returns (bool result) {
        if(frozenTokens[account] < _amount) {
            revert InsufficientBalance(_amount, frozenTokens[account]);
        }
        frozenTokens[account] -= _amount;
        emit unFrozen(account, _amount);
        return true;
    } 

    function freezeByAddress(address account) external onlyOwner returns (bool result) {
        if(allowList[account] == false) {
            revert NotFound();
        } else if (frozenTokens[account] == balanceOf[account]) {
            revert AlreadyFrozen(account);
        }
        frozenTokens[account] = balanceOf[account];
        emit Frozen(account, balanceOf[account]);
        return true;
    }
    
    function forcedTransfer(address from, address to, uint256 amount) external onlyOwner returns (bool result) {
        if(balanceOf[from] < amount) {
            revert InsufficientBalance(amount, balanceOf[from]);
        } 
        canReceive(to);

        uint256 fromFrozen = frozenTokens[from];

        

        balanceOf[from] -= amount;
        if (fromFrozen >= amount) {
            frozenTokens[from] -= amount;
        } else {
            frozenTokens[from] = 0;
        }
        balanceOf[to] += amount;
        emit forcedTransferSuccess(from, to, amount, balanceOf[from], fromFrozen);
        return true; 
    }
    
}