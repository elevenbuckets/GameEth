pragma solidity ^0.4.15;

contract SafeCal {
                function mul(uint a, uint b) public constant returns (uint);
                function sub(uint a, uint b) public constant returns (uint);
                function add(uint a, uint b) public constant returns (uint);
                function percent(uint numerator, uint denominator, uint precision) public constant returns(uint quotient);
                function ratio(uint quotient, uint precision, uint target) public constant returns(uint);
                function remains(uint quotient, uint precision, uint target) public constant returns(uint);
}

contract Calculate is SafeCal {
        function mul(uint a, uint b) public constant returns (uint) {
                uint c = a * b;
                assert(a == 0 || c / a == b);
                return c;
        }

        function sub(uint a, uint b) public constant returns (uint) {
                assert(b <= a);
                return a - b;
        }

        function add(uint a, uint b) public constant returns (uint) {
                uint c = a + b;
                assert(c >= a);
                return c;
        }

        function percent(uint numerator, uint denominator, uint precision) public constant returns(uint quotient) {
                uint _numerator = mul(numerator, 10 ** (precision+1));

                // with rounding of last digit
                //uint _quotient = add((_numerator / denominator), 5) / 10;

                // without rounding of last digit
                uint _quotient = (_numerator / denominator) / 10;

                return ( _quotient);
        }

        function ratio(uint quotient, uint precision, uint target) public constant returns(uint) {
                return mul(target, quotient) / precision;
        }

        function remains(uint quotient, uint precision, uint target) public constant returns(uint) {
                return sub(target, ratio(quotient, precision, target));
        }
}

