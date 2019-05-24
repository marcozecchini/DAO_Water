pragma solidity 0.4.25;

import "./oraclize.sol";
contract ProposalContract {

    function () public payable {}

    //Enum for elaborate the proposals
    enum Who {
        Home, //Monitor consumption of just a citizen
        Block, //Monitor consumption of a group of citizen
        Neighborhood //Monitor consumption of a larger group of citizen
    }
    enum Modes{
        LessThan, //The entity monitored must respect a certain threshold
        LessPossible //The entity monitored must consume less water as much as he can
    }
    enum Incentives {
        First, //The entities the consume less have the incentive
        WhoIsUnder, //The entities who respect a threshold have an incentive
        WhoIsUnderPercentage //The entities who reduce of a certain percentage have an incentive
    }
    enum Periods { //Period monitored after which incentives are distributed
        Month,
        Trimester,
        Semester
    }

    //Enum to control the diffent states
    enum Stages {
        Proposal,
        Selection,
        Running
    }

    address public owner;
    Stages public stage = Stages.Proposal;
    Who public who;
    Modes public mode;
    Incentives public incentive;
    Periods public period;
    mapping (address => uint) consumptions;
    //TODO: aggiungi balance nel caso questo contratto dovesse vincere

    //modifiers
    modifier atStage(Stages _stage){
        require(stage==_stage);
        _;
    }
    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }

    //events
    event SubmitProposal (address proposer, Who _who, Modes _mode, Incentives _incentive, Periods _period);
    event OwnerChanged (address _newOwner);
    event StageChanged(address _contract, Stages stage);

    //constructor
    function ProposalContract() public {
        owner = msg.sender;
    }

    function Propose (Who _who, Modes _mode, Incentives _incentive, Periods _period, address _address) public {
        who = _who;
        mode = _mode;
        incentive = _incentive;
        period = _period;
        addToManager(_address);
        emit SubmitProposal(msg.sender, who, mode, incentive, period);
    }

    function addToManager(address _address) internal {
        ManagerContract manager = ManagerContract(_address);
        manager.addProposalContract(this);
    }

    function changeStageToSelecting() public onlyBy(owner){
        stage = Stages.Selection;
        emit StageChanged(this, stage);
    }

    function changeStageToRunning() public onlyBy(owner){
        stage = Stages.Selection;
        emit StageChanged(this, stage);
    }

    function changeOwner(address _newOwner) public onlyBy(owner) {
        owner = _newOwner;
    }

    function runContract() public atStage(Stages.Running){
        //here the execution of the different cases
        WaterOracle oracle = WaterOracle(0);

    }

}

contract ManagerContract {

    struct Voter {
        uint weight;
        bool voted;
        uint8 vote;
    }

    //event
    event VoteStarted(uint _closingTime);
    event WinProposal(address _winner);
    event Voted(address _who, uint _amount);
    event AddedProposal(address _address);

    ProposalContract[] public proposals_list;
    uint[] proposals;
    ProposalContract public winner;

    address chairperson;
    bool startedVote;
    uint public closingTime;
    mapping(address => Voter) voters;
    uint public balanceTotal = 0;

    function() payable {}

    function addProposalContract (address _address) public {
        if (startedVote == true) return;
        ProposalContract prop = ProposalContract(_address);
        proposals_list.push(prop);
        emit AddedProposal(prop);
    }

    /// Create a new ballot with $(_numProposals) different proposals.
    function ManagerContract() public {
        chairperson = msg.sender;
        startedVote = false;
        voters[chairperson].weight = 1;
    }

    /// Give $(toVoter) the right to vote on this ballot.
    /// May only be called by $(chairperson).
    function giveRightToVote(address toVoter) public {
        if (msg.sender != chairperson || voters[toVoter].voted || startedVote == true) return;
        voters[toVoter].weight = 1;
    }

    /// Give a single vote to proposal $(toProposal).
    function vote(uint8 toProposal) public payable {
        require (msg.value > 0);
        Voter storage sender = voters[msg.sender];
        if (sender.voted || toProposal >= proposals.length) return;
        sender.voted = true;
        sender.vote = toProposal;

        //send money to manager
        balanceTotal += msg.value;
        proposals[toProposal] += sender.weight;

        emit Voted(msg.sender, msg.value);
    }

    //make the election start
    function startVote() public{
        if (startedVote && chairperson != msg.sender) return;
        //Change the stage to Selection
        for (uint8 contr = 0; contr < proposals_list.length; contr++){
            proposals_list[contr].changeStageToSelecting();
        }
        proposals.length = proposals_list.length;
        startedVote = true;
        closingTime = now + 60;
        emit VoteStarted(closingTime);
    }

    //choose the proposal that win the elections
    function winningProposal() public returns (uint8 _winningProposal){
        require(now > closingTime);

        uint256 winningVoteCount = 0;
        //if (now < closingTime) return;
        for (uint8 prop = 0; prop < proposals.length; prop++) {
            if (proposals[prop] > winningVoteCount) {
                winningVoteCount = proposals[prop];
                _winningProposal = prop;
            }
        }

        winner = proposals_list[_winningProposal];
        emit WinProposal(winner);
    }

    /* function to send the money when a propose win*/
    function trasferToWinner()  public returns (bool) {

        address(winner).transfer(address(this).balance);
        winner.changeStageToRunning();
        //winner.runContract();
        return true;
    }

    /* function to run the winner contract*/
    function runWinner() public {
        winner.runContract();
    }
}

contract WaterOracle is usingOraclize {
    string public water;

    event LogError(string error_message);
    event LogRequest(string message);
    event LogResponse(string water);

    function getWaterConsumption()
    public payable {
        if (oraclize_getPrice("URL") > this.balance) {
            emit LogError("Put more ETH to pay the query fee....");
        }
        else {
            emit LogRequest("Pending request, wait ...");
            oraclize_query("URL", ""); //TODO find the API
        }
    }

    function __callback(
        string memory _result) public
    {
        require(msg.sender == oraclize_cbAddress());
        emit LogResponse(_result);
        water = _result;
    }


}


//<ORACLIZE_API>