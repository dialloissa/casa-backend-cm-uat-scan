
set global net_read_timeout = 10800;
DROP PROCEDURE IF EXISTS getDailyDfspTransactionReport;


DELIMITER //


CREATE PROCEDURE getDailyDfspTransactionReport(
  START_DATE_TIME DATETIME,
  END_DATE_TIME DATETIME,
  FSP_ID VARCHAR(30)
)
-- =============================================
-- Author:      Shashikant Hirugade
-- Create date: 22/06/2020
-- Description: The daily transaction report for a dfsp (311)
--
-- Parameters:
--   @START_DATE_TIME - Start date for the report
--   @END_DATE_TIME - End date for the report
--   @FSP_ID - dfsp id
-- Returns:  List of the transactions in the given time window for the given dfsp id
--
-- Change History:
--   22/06/2020 Shashikant Hirugade: Initial version
-- =============================================
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SHOW ERRORS;
    ROLLBACK;
  END;
  START TRANSACTION;
  DROP TEMPORARY TABLE IF EXISTS transfers_data;
  CREATE TEMPORARY TABLE transfers_data
  SELECT
    q.quoteId AS quoteId
    , qpPayer.fspId AS senderDFSPName
    , payer.name AS originDFSPname
    , payee.name AS targetDFSPname
    , qpPayee.fspId AS receiverDFSPName
    , tx.transferId AS currentHubTransferID
    , IF(IFNULL(ftLegA.transferAId, ftLegB.transferAId) IS NULL, 'null', IFNULL(ftLegA.transferAId, ftLegB.transferAId)) AS parentTransferID
    , IF(IFNULL(ftLegA.transferBId, ftLegB.transferAId) IS NULL, 'null', IFNULL(ftLegA.transferBId, ftLegB.transferAId)) AS reciprocalHubTransferID
    , IF(txScn.name = 'TRANSFER', 'P2P', (IF(txScn.name = 'TRANSFER', 'MP', NULL))) AS transactionType
    , IF(q.transactionRequestId IS NULL, 'Original', 'Reversal') AS natureOfTxnType
    , CONCAT(SUBSTRING(DATE_FORMAT(q.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS requestDate
    , CONCAT(SUBSTRING(DATE_FORMAT(tx.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS createdDate
    , qpPayer.partyIdentifierValue AS senderId
    , qpPayee.partyIdentifierValue AS receiverId
    , IFNULL(ftLegA.exchangeRateId, ftLegB.exchangeRateId)  AS exchangeRateId
    , IF((partyPayee.firstName <> NULL && partyPayee.lastName <> NULL), 'RNR', 'RNND') AS receiverNameStatus
    , 'null' AS pricingOption
    , 'null' AS receiverKYCLevelStatus
    , IF(te.errorCode IS NULL, 'null', te.errorCode) AS errorCode
    , tx.transferId AS senderDFSPTxnID
    , tx.transferId AS receiverDFSPTxnID
    , ftLegA.fxQuoteAId AS legAQuoteAId
    , ftLegB.fxQuoteAId AS legBQuoteAId
    , IFNULL(ftLegA.transferAId, ftLegB.transferAId ) AS legATransferId
    , IFNULL(ftLegA.transferBId, ftLegB.transferBId) AS legBTransferId
  FROM
    transferParticipant txpPayer
  INNER JOIN
    transferParticipant txpPayee
    ON txpPayer.transferId = txpPayee.transferId
    AND txpPayer.transferParticipantId != txpPayee.transferParticipantId
  INNER JOIN
    transfer tx
    ON tx.transferId = txpPayer.transferId
  INNER JOIN
    transferParticipantRoleType txprt
    ON txprt.transferParticipantRoleTypeId = txpPayer.transferParticipantRoleTypeId
    AND txprt.name = 'PAYER_DFSP'
  INNER JOIN
    participantCurrency pcPayer
    ON pcPayer.participantCurrencyId = txpPayer.participantCurrencyId
  INNER JOIN
    participantCurrency pcPayee
    ON pcPayee.participantCurrencyId = txpPayee.participantCurrencyId
  INNER JOIN
    participant payer
    ON pcPayer.participantId = payer.participantId
  INNER JOIN
    participant payee
    ON pcPayee.participantId = payee.participantId
  INNER JOIN
    transactionReference txRef
    ON txRef.transactionReferenceId = tx.transferId
  INNER JOIN
    quote q
    ON q.quoteId = txRef.quoteId
  INNER JOIN
    transactionScenario txScn
    ON q.transactionScenarioId = txScn.transactionScenarioId
  INNER JOIN
    quoteParty qpPayer
    ON q.quoteId = qpPayer.quoteId
  INNER JOIN
    partyType ptPayer
    ON ptPayer.partyTypeId = qpPayer.partyTypeId AND ptPayer.name = 'PAYER'
  INNER JOIN
    quoteParty qpPayee
    ON q.quoteId = qpPayee.quoteId
  INNER JOIN
    partyType ptPayee
    ON ptPayee.partyTypeId = qpPayee.partyTypeId AND ptPayee.name = 'PAYEE'
  LEFT JOIN
    party partyPayee
    ON qpPayee.partyTypeId = partyPayee.partyId
  LEFT JOIN transferError te
    ON te.transferId = tx.transferId
  LEFT OUTER JOIN fxp_scheme_adapter.fxTransaction ftLegA
    ON ftLegA.transferAId = tx.transferId
  LEFT OUTER JOIN fxp_scheme_adapter.fxTransaction ftLegB
    ON ftLegB.transferBId = tx.transferId
  WHERE
    (payer.name = FSP_ID OR payee.name = FSP_ID)
    AND
    (q.createdDate BETWEEN START_DATE_TIME AND END_DATE_TIME);

  DROP TEMPORARY TABLE IF EXISTS transfers_states_legA;
  CREATE TEMPORARY TABLE transfers_states_legA
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legATransferId = tsc.transferId
    OR (legATransferId IS NULL AND currentHubTransferId = tsc.transferId)
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TEMPORARY TABLE IF EXISTS transfers_states_legB;
  CREATE TEMPORARY TABLE transfers_states_legB
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legBTransferId = tsc.transferId
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TEMPORARY TABLE IF EXISTS settlement_details_legA;
  CREATE TEMPORARY TABLE settlement_details_legA
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legATransferId = txf.transferId;

  DROP TEMPORARY TABLE IF EXISTS settlement_details_legB;
  CREATE TEMPORARY TABLE settlement_details_legB
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legBTransferId = txf.transferId;


  SELECT DISTINCT
    td.senderDFSPName
    , td.receiverDFSPName
    , td.currentHubTransferID AS currentTransferID
    , td.parentTransferID
    , td.reciprocalHubTransferID AS reciprocalTransferID
    , td.transactionType
    , td.natureOfTxnType
    , td.requestDate
    , td.createdDate
    , IF(legASettlement.settlementDate IS NULL, 'null', legASettlement.settlementDate) AS settlementDate
    , qr.transferAmountCurrencyId AS senderCurrency
    , IF(qr.payeeReceiveAmountCurrencyId IS NULL, qr.transferAmountCurrencyId, qr.payeeReceiveAmountCurrencyId) AS receiverCurrency
    , td.senderId
    , td.receiverId
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM qr.transferAmount)) AS senderAmount
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM IF(qr.payeeReceiveAmount IS NULL, qr.transferAmount, qr.payeeReceiveAmount))) AS receiverAmount
    , IF(ecr.rate / POW(10, ecr.decimals) IS NULL, 'null', CAST(ecr.rate / POW(10, ecr.decimals) AS CHAR)) AS forexRate
    , IF(cityRates.rateSetId IS NULL, 'null', CAST(cityRates.rateSetId AS CHAR)) AS fxRateSetID
    , IF((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) IS NULL, 'null', CAST((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) AS CHAR)) AS rounding
    , td.receiverNameStatus
    , td.pricingOption
    , td.receiverKYCLevelStatus
    , IF(legATransferStates.enumeration IS NULL, 'null', CAST(legATransferStates.enumeration AS CHAR)) AS senderTxStatus
    , IF(legBTransferStates.enumeration IS NULL, CAST(legATransferStates.enumeration AS CHAR), CAST(legBTransferStates.enumeration AS CHAR)) AS receiverTxStatus
    , CONCAT(SUBSTRING(DATE_FORMAT(legATransferStates.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS modificationDate
    , td.errorCode
    , td.senderDFSPTxnID
    , td.receiverDFSPTxnID
    , IF(legASettlement.settlementWindowId IS NULL, 'null', CAST(legASettlement.settlementWindowId AS CHAR)) AS senderSettlementWindowId
    , IF(legBSettlement.settlementWindowId IS NULL, 'null', CAST(legBSettlement.settlementWindowId AS CHAR)) AS receiverSettlementWindowId
    , IF(legASettlement.settlementState IS NULL, 'null', CAST(legASettlement.settlementState AS CHAR)) AS settlementState
    , IF(legASettlement.settlementStateChangeDate IS NULL, 'null', CAST(legASettlement.settlementStateChangeDate AS CHAR)) AS settlementStateChangeDate
  FROM  transfers_data td
  LEFT JOIN quoteResponse qr ON qr.quoteId = IFNULL(IFNULL(td.legAQuoteAId, td.legBQuoteAId), td.quoteId)
  LEFT JOIN fxp_server.exchange_channel_rates ecr ON ecr.id = td.exchangeRateId
  LEFT JOIN  fxp_server.citiExchangeRate cityRates ON cityRates.exchangeRateId = td.exchangeRateId
  LEFT JOIN transfers_states_legA legATransferStates ON legATransferStates.transferId = td.legATransferId OR (td.legATransferId IS NULL AND td.currentHubTransferId = legATransferStates.transferId)
  LEFT JOIN transfers_states_legB legBTransferStates ON legBTransferStates.transferId = td.legBTransferId
  LEFT JOIN settlement_details_legA legASettlement ON legASettlement.transferId = td.legATransferId
  LEFT JOIN settlement_details_legB legBSettlement ON legBSettlement.transferId = td.legBTransferId
  ORDER BY td.createdDate;
  COMMIT;

  DROP TEMPORARY TABLE IF EXISTS transfers_data;
  DROP TEMPORARY TABLE IF EXISTS transfers_states_legA;
  DROP TEMPORARY TABLE IF EXISTS transfers_states_legB;
  DROP TEMPORARY TABLE IF EXISTS settlement_details_legA;
  DROP TEMPORARY TABLE IF EXISTS settlement_details_legB;

END //


DROP PROCEDURE IF EXISTS getDailyHubTransactionReport;


CREATE PROCEDURE getDailyHubTransactionReport(
  START_DATE_TIME DATETIME,
  END_DATE_TIME DATETIME
)
-- =============================================
-- Author:      Shashikant Hirugade
-- Create date: 25/06/2020
-- Description: The daily hub transaction report (312)
--
-- Parameters:
--   @START_DATE_TIME - Start date for the report
--   @END_DATE_TIME - End date for the report
-- Returns:  List of the transactions in the given time window for
--
-- Change History:
--   25/06/2020 Shashikant Hirugade: Initial version
-- =============================================
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SHOW ERRORS;
    ROLLBACK;
  END;
  START TRANSACTION;
  DROP TEMPORARY TABLE IF EXISTS transfers_data;
  CREATE TEMPORARY TABLE transfers_data
  SELECT
    q.quoteId AS quoteId
    , qpPayer.fspId AS senderDFSPName
    , IF(payee.name IS NULL, 'null', payee.name) AS leg1vDFSP
    , IF(fxQuote.sourceFSP IS NULL, 'null', fxQuote.sourceFSP) AS leg2vDFSP
    , qpPayee.fspId AS receiverDFSPName
    , tx.transferId AS currentHubTransferID
    , IF(ftLegA.transferAId IS NULL, 'null', ftLegA.transferAId) AS parentTransferID
    , IF(ftLegA.transferBId IS NULL, 'null', ftLegA.transferBId) AS reciprocalHubTransferID
    , IF(txScn.name = 'TRANSFER', 'P2P', (IF(txScn.name = 'TRANSFER', 'MP', NULL))) AS transactionType
    , IF(q.transactionRequestId IS NULL, 'Original', 'Reversal') AS natureOfTxnType
    , CONCAT(SUBSTRING(DATE_FORMAT(q.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS requestDate
    , CONCAT(SUBSTRING(DATE_FORMAT(tx.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS createdDate
    , qpPayer.partyIdentifierValue AS senderId
    , qpPayee.partyIdentifierValue AS receiverId
    , ftLegA.exchangeRateId AS exchangeRateId
    , IF((partyPayee.firstName <> NULL && partyPayee.lastName <> NULL), 'RNR', 'RNND') AS receiverNameStatus
    , 'null' AS pricingOption
    , 'null' AS receiverKYCLevelStatus
    , IF(te.errorCode IS NULL, 'null', te.errorCode) AS errorCode
    , tx.transferId AS senderDFSPTxnID
    , tx.transferId AS receiverDFSPTxnID
    , ftLegA.fxQuoteAId AS legAQuoteAId
    , ftLegA.fxQuoteBId AS legBQuoteAId
    , ftLegA.transferAId AS legATransferId
    , ftLegA.transferBId AS legBTransferId
  FROM
    transferParticipant txpPayer
  INNER JOIN
    transferParticipant txpPayee
    ON txpPayer.transferId = txpPayee.transferId
    AND txpPayer.transferParticipantId != txpPayee.transferParticipantId
  INNER JOIN
    transfer tx
    ON tx.transferId = txpPayer.transferId
  INNER JOIN
    transferParticipantRoleType txprt
    ON txprt.transferParticipantRoleTypeId = txpPayer.transferParticipantRoleTypeId
    AND txprt.name = 'PAYER_DFSP'
  INNER JOIN
    participantCurrency pcPayer
    ON pcPayer.participantCurrencyId = txpPayer.participantCurrencyId
  INNER JOIN
    participantCurrency pcPayee
    ON pcPayee.participantCurrencyId = txpPayee.participantCurrencyId
  INNER JOIN
    participant payer
    ON pcPayer.participantId = payer.participantId
  INNER JOIN
    participant payee
    ON pcPayee.participantId = payee.participantId
  INNER JOIN
    transactionReference txRef
    ON txRef.transactionReferenceId = tx.transferId
  INNER JOIN
    quote q
    ON q.quoteId = txRef.quoteId
  INNER JOIN
    transactionScenario txScn
    ON q.transactionScenarioId = txScn.transactionScenarioId
  INNER JOIN
    quoteParty qpPayer
    ON q.quoteId = qpPayer.quoteId
  INNER JOIN
    partyType ptPayer
    ON ptPayer.partyTypeId = qpPayer.partyTypeId AND ptPayer.name = 'PAYER'
  INNER JOIN
    quoteParty qpPayee
    ON q.quoteId = qpPayee.quoteId
  INNER JOIN
    partyType ptPayee
    ON ptPayee.partyTypeId = qpPayee.partyTypeId AND ptPayee.name = 'PAYEE'
  LEFT JOIN
    party partyPayee
    ON qpPayee.partyTypeId = partyPayee.partyId
  LEFT JOIN transferError te
    ON te.transferId = tx.transferId
  LEFT JOIN fxp_scheme_adapter.fxTransaction ftLegA
    ON ftLegA.transferAId = tx.transferId
  LEFT JOIN fxp_scheme_adapter.fxQuote fxQuote
    ON fxQuote.fxQuoteId = ftLegA.fxQuoteBId
  WHERE
    payee.name != qpPayee.fspId -- this will eliminate the leg B transfers from the result
    AND
    (q.createdDate BETWEEN START_DATE_TIME AND END_DATE_TIME);

  DROP TEMPORARY TABLE IF EXISTS transfers_states_legA;
  CREATE TEMPORARY TABLE transfers_states_legA
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legATransferId = tsc.transferId
    OR (legATransferId IS NULL AND currentHubTransferId = tsc.transferId)
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TEMPORARY TABLE IF EXISTS transfers_states_legB;
  CREATE TEMPORARY TABLE transfers_states_legB
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legBTransferId = tsc.transferId
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TEMPORARY TABLE IF EXISTS settlement_details_legA;
  CREATE TEMPORARY TABLE settlement_details_legA
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legATransferId = txf.transferId;

  DROP TEMPORARY TABLE IF EXISTS settlement_details_legB;
  CREATE TEMPORARY TABLE settlement_details_legB
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legBTransferId = txf.transferId;


  SELECT DISTINCT
    td.senderDFSPname AS senderDFSPName
    , td.leg1vDFSP AS leg1vDFSP
    , td.leg2vDFSP AS leg2vDFSP
    , td.receiverDFSPname AS receiverDFSPName
    , td.currentHubTransferID AS senderTransferID
    , td.parentTransferID
    , td.reciprocalHubTransferID AS receiverTransferID
    , td.transactionType
    , td.natureOfTxnType
    , td.requestDate
    , td.createdDate
    , IF(legASettlement.settlementDate IS NULL, 'null', legASettlement.settlementDate) AS settlementDate
    , qr.transferAmountCurrencyId AS senderCurrency
    , qr.payeeReceiveAmountCurrencyId AS receiverCurrency
    , td.senderId
    , td.receiverId
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM qr.transferAmount)) AS senderAmount
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM IF(qr.payeeReceiveAmount IS NULL, qr.transferAmount, qr.payeeReceiveAmount))) AS receiverAmount
    , IF(ecr.rate / POW(10, ecr.decimals) IS NULL, 'null', CAST(ecr.rate / POW(10, ecr.decimals) AS CHAR)) AS forexRate
    , IF(cityRates.rateSetId IS NULL, 'null', CAST(cityRates.rateSetId AS CHAR)) AS fxRateSetID
    , IF((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) IS NULL, 'null', CAST((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) AS CHAR)) AS rounding
    , td.receiverNameStatus
    , td.pricingOption
    , td.receiverKYCLevelStatus
    , IF(legATransferStates.enumeration IS NULL, 'null', CAST(legATransferStates.enumeration AS CHAR)) AS senderTxStatus
    , IF(legBTransferStates.enumeration IS NULL, 'null', CAST(legBTransferStates.enumeration AS CHAR)) AS receiverTxStatus
    , CONCAT(SUBSTRING(DATE_FORMAT(legATransferStates.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS modificationDate
    , td.errorCode
    , td.senderDFSPTxnID
    , td.receiverDFSPTxnID
    , IF(legASettlement.settlementWindowId IS NULL, 'null', CAST(legASettlement.settlementWindowId AS CHAR)) AS senderSettlementWindowId
    , IF(legBSettlement.settlementWindowId IS NULL, 'null', CAST(legBSettlement.settlementWindowId AS CHAR)) AS receiverSettlementWindowId
    , IF(legASettlement.settlementState IS NULL, 'null', CAST(legASettlement.settlementState AS CHAR)) AS settlementState
    , IF(legASettlement.settlementStateChangeDate IS NULL, 'null', CAST(legASettlement.settlementStateChangeDate AS CHAR)) AS settlementStateChangeDate
  FROM  transfers_data td
  LEFT JOIN quoteResponse qr ON qr.quoteId = IFNULL(IFNULL(td.legAQuoteAId, td.legBQuoteAId), td.quoteId)
  LEFT JOIN fxp_server.exchange_channel_rates ecr ON ecr.id = td.exchangeRateId
  LEFT JOIN  fxp_server.citiExchangeRate cityRates ON cityRates.exchangeRateId = td.exchangeRateId
  LEFT JOIN transfers_states_legA legATransferStates ON legATransferStates.transferId = td.legATransferId OR (td.legATransferId IS NULL AND td.currentHubTransferId = legATransferStates.transferId)
  LEFT JOIN transfers_states_legB legBTransferStates ON legBTransferStates.transferId = td.legBTransferId
  LEFT JOIN settlement_details_legA legASettlement ON legASettlement.transferId = td.legATransferId
  LEFT JOIN settlement_details_legB legBSettlement ON legBSettlement.transferId = td.legBTransferId
  ORDER BY td.createdDate;
  COMMIT;

  DROP TEMPORARY TABLE IF EXISTS transfers_data;
  DROP TEMPORARY TABLE IF EXISTS transfers_states_legA;
  DROP TEMPORARY TABLE IF EXISTS transfers_states_legB;
  DROP TEMPORARY TABLE IF EXISTS settlement_details_legA;
  DROP TEMPORARY TABLE IF EXISTS settlement_details_legB;

END //



DROP PROCEDURE IF EXISTS getDailyHubTransactionReportGebeya;


CREATE PROCEDURE getDailyHubTransactionReportGebeya(
  START_DATE_TIME DATETIME,
  END_DATE_TIME DATETIME
)
-- =============================================
-- Author:      Jules Boris KREME
-- Create date: 21/01/2021
-- Description: The daily hub transaction report (312 gebeya)
--
-- Parameters:
--   @START_DATE_TIME - Start date for the report
--   @END_DATE_TIME - End date for the report
-- Returns:  List of the transactions in the given time window for
--
-- Change History:
--   25/06/2020 Shashikant Hirugade: Initial version
-- =============================================
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SHOW ERRORS;
    ROLLBACK;
  END;
  START TRANSACTION;
  DROP TABLE IF EXISTS transfers_data;
  CREATE TEMPORARY TABLE transfers_data
  SELECT
    q.quoteId AS quoteId
    , qpPayer.fspId AS senderDFSPName
    , IF(payee.name IS NULL, 'null', payee.name) AS leg1vDFSP
    , IF(fxQuote.sourceFSP IS NULL, 'null', fxQuote.sourceFSP) AS leg2vDFSP
    , qpPayee.fspId AS receiverDFSPName
    , tx.transferId AS currentHubTransferID
    , IF(ftLegA.transferAId IS NULL, 'null', ftLegA.transferAId) AS parentTransferID
    , IF(ftLegA.transferBId IS NULL, 'null', ftLegA.transferBId) AS reciprocalHubTransferID
    , IF(txScn.name = 'TRANSFER', 'P2P', (IF(txScn.name = 'TRANSFER', 'MP', NULL))) AS transactionType
    , IF(q.transactionRequestId IS NULL, 'Original', 'Reversal') AS natureOfTxnType
    , CONCAT(SUBSTRING(DATE_FORMAT(q.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS requestDate
    , CONCAT(SUBSTRING(DATE_FORMAT(tx.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS createdDate
    , ftLegA.exchangeRateId AS exchangeRateId
    , IF((partyPayee.firstName <> NULL && partyPayee.lastName <> NULL), 'RNR', 'RNND') AS receiverNameStatus
    , 'null' AS pricingOption
    , 'null' AS receiverKYCLevelStatus
    , IF(te.errorCode IS NULL, 'null', te.errorCode) AS errorCode
    , tx.transferId AS senderDFSPTxnID
    , tx.transferId AS receiverDFSPTxnID
    , ftLegA.fxQuoteAId AS legAQuoteAId
    , ftLegA.fxQuoteBId AS legBQuoteAId
    , ftLegA.transferAId AS legATransferId
    , ftLegA.transferBId AS legBTransferId
  FROM
    transferParticipant txpPayer
  INNER JOIN
    transferParticipant txpPayee
    ON txpPayer.transferId = txpPayee.transferId
    AND txpPayer.transferParticipantId != txpPayee.transferParticipantId
  INNER JOIN
    transfer tx
    ON tx.transferId = txpPayer.transferId
  INNER JOIN
    transferParticipantRoleType txprt
    ON txprt.transferParticipantRoleTypeId = txpPayer.transferParticipantRoleTypeId
    AND txprt.name = 'PAYER_DFSP'
  INNER JOIN
    participantCurrency pcPayer
    ON pcPayer.participantCurrencyId = txpPayer.participantCurrencyId
  INNER JOIN
    participantCurrency pcPayee
    ON pcPayee.participantCurrencyId = txpPayee.participantCurrencyId
  INNER JOIN
    participant payer
    ON pcPayer.participantId = payer.participantId
  INNER JOIN
    participant payee
    ON pcPayee.participantId = payee.participantId
  INNER JOIN
    transactionReference txRef
    ON txRef.transactionReferenceId = tx.transferId
  INNER JOIN
    quote q
    ON q.quoteId = txRef.quoteId
  INNER JOIN
    transactionScenario txScn
    ON q.transactionScenarioId = txScn.transactionScenarioId
  INNER JOIN
    quoteParty qpPayer
    ON q.quoteId = qpPayer.quoteId
  INNER JOIN
    partyType ptPayer
    ON ptPayer.partyTypeId = qpPayer.partyTypeId AND ptPayer.name = 'PAYER'
  INNER JOIN
    quoteParty qpPayee
    ON q.quoteId = qpPayee.quoteId
  INNER JOIN
    partyType ptPayee
    ON ptPayee.partyTypeId = qpPayee.partyTypeId AND ptPayee.name = 'PAYEE'
  LEFT JOIN
    party partyPayee
    ON qpPayee.partyTypeId = partyPayee.partyId
  LEFT JOIN transferError te
    ON te.transferId = tx.transferId
  LEFT JOIN fxp_scheme_adapter.fxTransaction ftLegA
    ON ftLegA.transferAId = tx.transferId
  LEFT JOIN fxp_scheme_adapter.fxQuote fxQuote
    ON fxQuote.fxQuoteId = ftLegA.fxQuoteBId
  WHERE
    payee.name != qpPayee.fspId -- this will eliminate the leg B transfers from the result
    AND
    (q.createdDate BETWEEN START_DATE_TIME AND END_DATE_TIME);

  DROP TABLE IF EXISTS transfers_states_legA;
  CREATE TEMPORARY TABLE transfers_states_legA
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legATransferId = tsc.transferId
    OR (legATransferId IS NULL AND currentHubTransferId = tsc.transferId)
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TABLE IF EXISTS transfers_states_legB;
  CREATE TEMPORARY TABLE transfers_states_legB
  SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate, tst.enumeration
  FROM
    transferStateChange tsc
  INNER JOIN
    (SELECT MAX(tsc.transferStateChangeId) AS transferStateChangeId, tsc.transferId FROM transferStateChange tsc GROUP BY transferId) mtsc
    ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  INNER JOIN
    transferState tst
    ON tsc.transferStateId = tst.transferStateId
  INNER JOIN
    transfers_data
    ON legBTransferId = tsc.transferId
  WHERE
    tst.enumeration IN ('COMMITTED', 'RESERVED', 'ABORTED');

  DROP TABLE IF EXISTS settlement_details_legA;
  CREATE TEMPORARY TABLE settlement_details_legA
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legATransferId = txf.transferId;

  DROP TABLE IF EXISTS settlement_details_legB;
  CREATE TEMPORARY TABLE settlement_details_legB
  SELECT
    txf.transferId
    , IF(ssc.settlementStateId = 'SETTLED', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z'), 'null') AS settlementDate
    , IF(txf.settlementWindowId IS NULL, 'null', CAST(txf.settlementWindowId AS CHAR)) AS settlementWindowId
    , IF(ssc.settlementStateId IS NULL, 'null', ssc.settlementStateId) AS settlementState
    , IF(ssc.createdDate IS NULL, 'null', CONCAT(SUBSTRING(DATE_FORMAT(ssc.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z')) AS settlementStateChangeDate
  FROM
    transferFulfilment txf
  LEFT JOIN
    settlementSettlementWindow ssw
    ON ssw.settlementWindowId = txf.settlementWindowId
  LEFT JOIN
    settlement sett
    ON sett.settlementId = ssw.settlementId
  LEFT JOIN
    settlementStateChange ssc
    ON ssc.settlementStateChangeId = sett.currentStateChangeId
  INNER JOIN transfers_data ON legBTransferId = txf.transferId;


  SELECT DISTINCT
    td.senderDFSPname AS senderDFSPName
    , td.leg1vDFSP AS leg1vDFSP
    , td.leg2vDFSP AS leg2vDFSP
    , td.receiverDFSPname AS receiverDFSPName
    , td.currentHubTransferID AS senderTransferID
    , td.parentTransferID
    , td.reciprocalHubTransferID AS receiverTransferID
    , td.transactionType
    , td.natureOfTxnType
    , td.requestDate
    , td.createdDate
    , IF(legASettlement.settlementDate IS NULL, 'null', legASettlement.settlementDate) AS settlementDate
    , qr.transferAmountCurrencyId AS senderCurrency
    , qr.payeeReceiveAmountCurrencyId AS receiverCurrency
    , td.senderId
    , td.receiverId
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM qr.transferAmount)) AS senderAmount
    , TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM IF(qr.payeeReceiveAmount IS NULL, qr.transferAmount, qr.payeeReceiveAmount))) AS receiverAmount
    , IF(ecr.rate / POW(10, ecr.decimals) IS NULL, 'null', CAST(ecr.rate / POW(10, ecr.decimals) AS CHAR)) AS forexRate
    , IF(cityRates.rateSetId IS NULL, 'null', CAST(cityRates.rateSetId AS CHAR)) AS fxRateSetID
    , IF((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) IS NULL, 'null', CAST((qr.transferAmount * (ecr.rate / POW(10, ecr.decimals)) - qr.payeeReceiveAmount) AS CHAR)) AS rounding
    , td.receiverNameStatus
    , td.pricingOption
    , td.receiverKYCLevelStatus
    , IF(legATransferStates.enumeration IS NULL, 'null', CAST(legATransferStates.enumeration AS CHAR)) AS senderTxStatus
    , IF(legBTransferStates.enumeration IS NULL, 'null', CAST(legBTransferStates.enumeration AS CHAR)) AS receiverTxStatus
    , CONCAT(SUBSTRING(DATE_FORMAT(legATransferStates.createdDate, '%Y-%m-%dT%T.%f'), 1, 23), 'Z') AS modificationDate
    , td.errorCode
    , td.senderDFSPTxnID
    , td.receiverDFSPTxnID
    , IF(legASettlement.settlementWindowId IS NULL, 'null', CAST(legASettlement.settlementWindowId AS CHAR)) AS senderSettlementWindowId
    , IF(legBSettlement.settlementWindowId IS NULL, 'null', CAST(legBSettlement.settlementWindowId AS CHAR)) AS receiverSettlementWindowId
    , IF(legASettlement.settlementState IS NULL, 'null', CAST(legASettlement.settlementState AS CHAR)) AS settlementState
    , IF(legASettlement.settlementStateChangeDate IS NULL, 'null', CAST(legASettlement.settlementStateChangeDate AS CHAR)) AS settlementStateChangeDate
  FROM  transfers_data td
  LEFT JOIN quoteResponse qr ON qr.quoteId = IFNULL(IFNULL(td.legAQuoteAId, td.legBQuoteAId), td.quoteId)
  LEFT JOIN fxp_server.exchange_channel_rates ecr ON ecr.id = td.exchangeRateId
  LEFT JOIN  fxp_server.citiExchangeRate cityRates ON cityRates.exchangeRateId = td.exchangeRateId
  LEFT JOIN transfers_states_legA legATransferStates ON legATransferStates.transferId = td.legATransferId OR (td.legATransferId IS NULL AND td.currentHubTransferId = legATransferStates.transferId)
  LEFT JOIN transfers_states_legB legBTransferStates ON legBTransferStates.transferId = td.legBTransferId
  LEFT JOIN settlement_details_legA legASettlement ON legASettlement.transferId = td.legATransferId
  LEFT JOIN settlement_details_legB legBSettlement ON legBSettlement.transferId = td.legBTransferId
  ORDER BY td.createdDate;
  COMMIT;

  DROP TABLE IF EXISTS transfers_data;
  DROP TABLE IF EXISTS transfers_states_legA;
  DROP TABLE IF EXISTS transfers_states_legB;
  DROP TABLE IF EXISTS settlement_details_legA;
  DROP TABLE IF EXISTS settlement_details_legB;

END //


DELIMITER ;