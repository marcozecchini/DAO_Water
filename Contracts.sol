pragma solidity 0.4.26;
import "./Oraclize.sol";

contract ProposalContract{

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
    WaterOracle public waterOracle;

    //To keep track of the consumption of each consumers
    mapping (string => uint) consumptions;

    //To keep track of the consumers and their addresses
    mapping (string => address) consumers;
    string[] array_consumers;

    //modifiers
    modifier atStage(Stages _stage){
        require(stage==_stage);
        _;
    }
    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }


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
    }

    function addToManager(address _address) internal {
        ManagerContract manager = ManagerContract(_address);
        manager.addProposalContract(this);
    }

    function nextStage() public onlyBy(owner){
        stage = Stages(uint(stage)+1);
    }


    function changeOwner(address _newOwner) public onlyBy(owner) {
        owner = _newOwner;
    }

    function addConsumer (string _name) public atStage(Stages.Running){
        consumers[_name] = msg.sender;
        consumptions[_name] = 0;
        array_consumers.push(_name);

    }

    function addWaterOracle(address _address) public {
        waterOracle = WaterOracle (_address);
    }

    function runContract(string consumer, string revenue_month) public payable atStage(Stages.Running){
        //here the execution of the different cases
        string memory who_oracle;
        if (who == Who.Home) {
            who_oracle = "meter_number";
        }
        else if (who == Who.Block) {
            who_oracle = "development_name";
        }
        else if (who == Who.Neighborhood) {
            who_oracle = "borough";
        }
        for (uint i = 0; i < array_consumers.length; i++){
            address(waterOracle).transfer(msg.value);
            waterOracle.getWaterConsumption(who_oracle, array_consumers[i], revenue_month, this.insertConsumption);

        }
    }

    function insertConsumption(string _name, uint _amount) public onlyBy(waterOracle){
        consumptions[_name] = _amount;
        //Redistribution of incentives, JUST CASE FOR LessThan
        if (_amount < 500){
            consumers[_name].transfer(100);
        }
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
        require (msg.value > 999);
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
            proposals_list[contr].nextStage();
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
        balanceTotal = 0;
        winner.nextStage();
        //winner.runContract();
        return true;
    }


}

contract WaterOracle is usingOraclize {
    uint public water;
    ProposalContract proposal;
    struct Request{
        string name;
        function ( string memory _name, uint result) external callback;
    }
    mapping (bytes32 => Request) requests;

    event LogError(string error_message);
    event LogRequest(string message, bytes32 request_id, string name);
    event LogResponse(bytes32 myid, string water);

    function () public  payable {
    }

    function getWaterConsumption(string who, string name, string revenue_month, function ( string memory _name, uint result) external callback)
    public {
        proposal = ProposalContract(msg.sender);

        if (oraclize_getPrice("URL") > this.balance) {
            emit LogError("Put more ETH to pay the query fee....");
        }
        else {

            bytes32 id = oraclize_query("URL", string(abi.encodePacked("json(https://data.cityofnewyork.us/resource/66be-66yr.json?", who,"=",name,"&revenue_month=",revenue_month,").0.consumption_hcf"
                )));
            requests[id] = Request(name,callback);
            emit LogRequest("Pending request, wait ...", id,name);


            //oraclize_query("URL", "json(https://data.cityofnewyork.us/resource/66be-66yr.json?development_name=ARMSTRONG%20I&revenue_month=2013-03-01).0.consumption_hcf");
            //RETRIEVE JSON DATA:
            //1. consumption_hcf : consumptions in hundreds of cubic foot
            //2a. borough : Neighborhood , 2b. development_name : Block, 2c. meter_number: Single citizen
            //3. revenue_month in this way : 2014-04-01
        }
    }

    function __callback(bytes32 myid,
        string _result) public
    {
        require(msg.sender == oraclize_cbAddress());
        emit LogResponse(myid, _result);
        water = parseInt(_result);
        requests[myid].callback(requests[myid].name,water);

    }


}