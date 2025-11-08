import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // For ImageFilter.blur

/* ============================
  Local Storage Simulation (Replaces shared_preferences)
  ============================ */
class LocalDataService {
  static String? _simulatedStorage; // Represents the physical device storage

  /// Simulates saving data asynchronously to local storage
  Future<void> save(String data) async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate IO delay
    _simulatedStorage = data;
    print('[LocalDataService] Quote Draft saved.');
  }

  /// Simulates loading data asynchronously from local storage
  Future<String?> load() async {
    await Future.delayed(const Duration(milliseconds: 200)); // Simulate IO delay
    return _simulatedStorage;
  }
}

/* ============================
  Models
  ============================ */

class QuoteItem {
  String name;
  double qty;
  double rate;
  double discount; // absolute amount per unit
  double taxPct; // e.g., 18.0

  QuoteItem({
    this.name = '',
    this.qty = 0.0,
    this.rate = 0.0,
    this.discount = 0.0,
    this.taxPct = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'rate': rate,
    'discount': discount,
    'taxPct': taxPct,
  };

  factory QuoteItem.fromJson(Map<String, dynamic> j) => QuoteItem(
    name: j['name'] ?? '',
    qty: (j['qty'] ?? 1).toDouble(),
    rate: (j['rate'] ?? 0).toDouble(),
    discount: (j['discount'] ?? 0).toDouble(),
    taxPct: (j['taxPct'] ?? 0).toDouble(),
  );
}

enum QuoteStatus { Draft, Sent, Accepted }

class Quote {
  String clientName;
  String clientAddress;
  String reference;
  List<QuoteItem> items;
  bool taxInclusive; // false = tax-exclusive, true = tax-inclusive
  String currencyCode; // e.g. "INR"

  Quote({
    this.clientName = '',
    this.clientAddress = '',
    this.reference = '',
    this.items = const [],
    this.taxInclusive = false,
    this.currencyCode = 'INR',
  });

  Map<String, dynamic> toJson() => {
    'clientName': clientName,
    'clientAddress': clientAddress,
    'reference': reference,
    'items': items.map((i) => i.toJson()).toList(),
    'taxInclusive': taxInclusive,
    'currencyCode': currencyCode,
  };

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
    clientName: j['clientName'] ?? '',
    clientAddress: j['clientAddress'] ?? '',
    reference: j['reference'] ?? '',
    items:
    (j['items'] as List? ?? []).map((e) => QuoteItem.fromJson(e)).toList(),
    taxInclusive: j['taxInclusive'] ?? false,
    currencyCode: j['currencyCode'] ?? 'INR',
  );
}

/* ============================
  Calculation utilities
  ============================ */

class CalcResult {
  final double net; // base without tax
  final double tax;
  final double total; // net + tax (or gross if inclusive)

  CalcResult({required this.net, required this.tax, required this.total});
}

CalcResult calculateItemTotal(QuoteItem it, {required bool taxInclusive}) {
  final effectiveRate = (it.rate - it.discount);
  final base = effectiveRate * it.qty; // gross when inclusive, net when exclusive
  if (!taxInclusive) {
    final tax = base * (it.taxPct / 100.0);
    final total = base + tax;
    return CalcResult(net: base, tax: tax, total: total);
  } else {
    final net = base / (1 + (it.taxPct / 100.0));
    final tax = base - net;
    return CalcResult(net: net, tax: tax, total: base);
  }
}

String formatCurrency(double val, {String code = 'INR'}) {
  try {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return f.format(val);
  } catch (e) {
    return '${val.toStringAsFixed(2)} $code';
  }
}

/* ============================
  Provider
  ============================ */

class QuoteProvider extends ChangeNotifier {
  Quote quote = Quote(items: [
    // Initial item added so the list isn't empty on load
  ]);
  final LocalDataService _storageService = LocalDataService();
  bool _isLoading = false;
  QuoteStatus _status = QuoteStatus.Draft;

  bool get isLoading => _isLoading;
  QuoteStatus get status => _status;

  QuoteProvider() {
    _loadQuote();
  }

  // --- Status & Storage Methods ---

  void setStatus(QuoteStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  Future<void> _loadQuote() async {
    _isLoading = true;
    notifyListeners();
    try {
      final jsonString = await _storageService.load();
      if (jsonString != null && jsonString.isNotEmpty) {
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        quote = Quote.fromJson(jsonMap);
        _status = QuoteStatus.Draft;
        print('Quote draft loaded successfully.');
      }
    } catch (e) {
      print('Error loading quote: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveQuote() async {
    try {
      final jsonString = json.encode(quote.toJson());
      await _storageService.save(jsonString);
      _status = QuoteStatus.Draft; // Set status to Draft upon save
      notifyListeners();
    } catch (e) {
      print('Error saving quote: $e');
    }
  }

  // --- State Modification Methods ---

  void setClientInfo({String? name, String? address, String? reference}) {
    if (name != null) quote.clientName = name;
    if (address != null) quote.clientAddress = address;
    if (reference != null) quote.reference = reference;
    notifyListeners();
  }

  void toggleTaxInclusive(bool v) {
    quote.taxInclusive = v;
    notifyListeners();
  }

  void addItem() {
    quote.items = [...quote.items, QuoteItem()];
    notifyListeners();
  }

  void removeItem(int index) {
    if (quote.items.length <= 1) return;
    final items = [...quote.items];
    items.removeAt(index);
    quote.items = items;
    notifyListeners();
  }

  void updateItem(int index, QuoteItem item) {
    final items = [...quote.items];
    items[index] = item;
    quote.items = items;
    notifyListeners();
  }

  // Calculations
  double get subtotal {
    double s = 0;
    for (var it in quote.items) {
      final res = calculateItemTotal(it, taxInclusive: quote.taxInclusive);
      s += res.net;
    }
    return s;
  }

  double get totalTax {
    double t = 0;
    for (var it in quote.items) {
      final res = calculateItemTotal(it, taxInclusive: quote.taxInclusive);
      t += res.tax;
    }
    return t;
  }

  double get grandTotal {
    double g = 0;
    for (var it in quote.items) {
      final res = calculateItemTotal(it, taxInclusive: quote.taxInclusive);
      g += res.total;
    }
    return g;
  }
}

/* ============================
  Styling Helpers (from v2)
  ============================ */

Widget _buildGlassmorphicCard(BuildContext context, {required Widget child}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.4), // Semi-transparent background
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

Widget _buildGradientButton({
  required BuildContext context,
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
  required List<Color> gradientColors,
}) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: gradientColors[0].withOpacity(0.4),
          blurRadius: 15,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent, // Make button transparent to show gradient
        shadowColor: Colors.transparent, // Remove default shadow
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
/* ============================
  Widgets: LineItemRow
  ============================ */

class LineItemRow extends StatefulWidget {
  final QuoteItem item;
  final ValueChanged<QuoteItem> onChanged;
  final VoidCallback onRemove;
  final bool canRemove;
  final int index;

  const LineItemRow({
    Key? key,
    required this.item,
    required this.onChanged,
    required this.onRemove,
    required this.index,
    this.canRemove = true,
  }) : super(key: key);

  @override
  State<LineItemRow> createState() => _LineItemRowState();
}

class _LineItemRowState extends State<LineItemRow> {
  // Use local controllers for smoother text input experience
  late TextEditingController nameC;
  late TextEditingController qtyC;
  late TextEditingController rateC;
  late TextEditingController discountC;
  late TextEditingController taxC;

  @override
  void initState() {
    super.initState();
    nameC = TextEditingController(text: widget.item.name);
    // Initialize with empty string if value is 0.0, so hintText is visible
    qtyC = TextEditingController(text: widget.item.qty == 0.0 ? '' : widget.item.qty.toString());
    rateC = TextEditingController(text: widget.item.rate == 0.0 ? '' : widget.item.rate.toString());
    discountC = TextEditingController(text: widget.item.discount == 0.0 ? '' : widget.item.discount.toString());
    taxC = TextEditingController(text: widget.item.taxPct == 0.0 ? '' : widget.item.taxPct.toString());

    nameC.addListener(upd);
    qtyC.addListener(upd);
    rateC.addListener(upd);
    discountC.addListener(upd);
    taxC.addListener(upd);
  }

  @override
  void didUpdateWidget(covariant LineItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.name != widget.item.name) nameC.text = widget.item.name;
    // Update logic to only set text if it's non-zero or different, otherwise use empty string
    if (oldWidget.item.qty != widget.item.qty) qtyC.text = widget.item.qty == 0.0 ? '' : widget.item.qty.toString();
    if (oldWidget.item.rate != widget.item.rate) rateC.text = widget.item.rate == 0.0 ? '' : widget.item.rate.toString();
    if (oldWidget.item.discount != widget.item.discount) discountC.text = widget.item.discount == 0.0 ? '' : widget.item.discount.toString();
    if (oldWidget.item.taxPct != widget.item.taxPct) taxC.text = widget.item.taxPct == 0.0 ? '' : widget.item.taxPct.toString();
  }

  void upd() {
    final it = QuoteItem(
      name: nameC.text,
      // If text is empty, parse as 0.0
      qty: double.tryParse(qtyC.text) ?? 0.0,
      rate: double.tryParse(rateC.text) ?? 0.0,
      discount: double.tryParse(discountC.text) ?? 0.0,
      taxPct: double.tryParse(taxC.text) ?? 0.0,
    );
    widget.onChanged(it);
  }

  @override
  void dispose() {
    nameC.dispose();
    qtyC.dispose();
    rateC.dispose();
    discountC.dispose();
    taxC.dispose();
    super.dispose();
  }

  // --- MODIFIED METHOD: Added hintText logic for numeric fields ---
  Widget _buildField({
    required TextEditingController controller,
    required String labelText,
    bool isNumeric = false,
    int flex = 1,
    TextAlign align = TextAlign.left,
  }) {
    // Determine the text to use as a hint/label
    final String hint = isNumeric ? 'Enter $labelText' : labelText;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            // Use hintText for numerical fields for better guidance when empty
            hintText: isNumeric ? hint : null,
            // Keep labelText for non-numeric field (Product Name)
            labelText: isNumeric ? null : hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            floatingLabelBehavior: FloatingLabelBehavior.never, // Clean look for all fields
          ),
          style: const TextStyle(fontSize: 14),
          textAlign: align,
          keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: isNumeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
              : null,
        ),
      ),
    );
  }

  // --- MODIFIED METHOD: Added hintText logic for numeric fields ---
  Widget _buildSimpleFieldContent({
    required TextEditingController controller,
    required String labelText,
    bool isNumeric = false,
  }) {
    // Determine the text to use as a hint/label
    final String hint = isNumeric ? 'Enter $labelText' : labelText;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          // Use hintText for numerical fields for better guidance when empty
          hintText: isNumeric ? hint : null,
          // Keep labelText for non-numeric field
          labelText: isNumeric ? null : hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          floatingLabelBehavior: FloatingLabelBehavior.never, // Clean look for all fields
        ),
        style: const TextStyle(fontSize: 14),
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        inputFormatters: isNumeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QuoteProvider>(context);
    final isWide = MediaQuery.of(context).size.width > 700;
    final itemTotal = calculateItemTotal(widget.item, taxInclusive: qp.quote.taxInclusive).total;

    // Styling constants
    const totalTextStyle = TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF00C853), fontSize: 15);

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            _buildField(controller: nameC, labelText: 'Product / Service', flex: 3),
            _buildField(controller: qtyC, labelText: 'Qty', isNumeric: true, align: TextAlign.center),
            _buildField(controller: rateC, labelText: 'Rate', isNumeric: true, flex: 2, align: TextAlign.center),
            _buildField(controller: discountC, labelText: 'Discount', isNumeric: true, flex: 2, align: TextAlign.center),
            _buildField(controller: taxC, labelText: 'Tax %', isNumeric: true, flex: 1, align: TextAlign.center),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(formatCurrency(itemTotal, code: qp.quote.currencyCode), style: totalTextStyle, textAlign: TextAlign.right),
              ),
            ),
            if (widget.canRemove)
              SizedBox(
                width: 32,
                child: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: widget.onRemove),
              )
          ],
        ),
      );
    } else {
      return _buildGlassmorphicCard(
        context,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSimpleFieldContent(controller: nameC, labelText: 'Product / Service'), // NO Expanded
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildField(controller: qtyC, labelText: 'Qty', isNumeric: true), // Expanded is fine here (inside Row)
                  _buildField(controller: rateC, labelText: 'Rate', isNumeric: true), // Expanded is fine here (inside Row)
                ],
              ),
              Row(
                children: [
                  _buildField(controller: discountC, labelText: 'Discount', isNumeric: true), // Expanded is fine here (inside Row)
                  _buildField(controller: taxC, labelText: 'Tax %', isNumeric: true), // Expanded is fine here (inside Row)
                ],
              ),
              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total: ${formatCurrency(itemTotal, code: qp.quote.currencyCode)}', style: totalTextStyle),
                if (widget.canRemove)
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: widget.onRemove)
              ]),
            ],
          ),
        ),
      );
    }
  }
}

/* ============================
  Widgets: QuoteForm
  ============================ */

class QuoteForm extends StatelessWidget {
  const QuoteForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<QuoteProvider>(builder: (context, qp, _) {
      if (qp.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }


      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Client & Quote Details', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          _buildGlassmorphicCard(
            context,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: qp.quote.clientName,
                    decoration: const InputDecoration(labelText: 'Client Name'),
                    onChanged: (v) => qp.setClientInfo(name: v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: qp.quote.clientAddress,
                    decoration: const InputDecoration(labelText: 'Client Address'),
                    onChanged: (v) => qp.setClientInfo(address: v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: qp.quote.reference,
                    decoration: const InputDecoration(labelText: 'Reference / PO'),
                    onChanged: (v) => qp.setClientInfo(reference: v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Line Items', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
            Row(children: [
              const Text('Tax Inclusive'),
              Switch(value: qp.quote.taxInclusive, onChanged: qp.toggleTaxInclusive),
            ])
          ]),
          const SizedBox(height: 16),
          _buildGlassmorphicCard(
            context,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Wide Screen Header (FIX 1: Adjusted Expanded and added SizedBox)
                  if (MediaQuery.of(context).size.width > 700)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                      child: Row(
                        children: const [
                          Expanded(flex: 3, child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                          Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Discount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text('Tax %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                          SizedBox(width: 32), // Space for Delete Button
                        ],
                      ),
                    ),
                  const Divider(color: Colors.white30, height: 1),
                  ...List.generate(qp.quote.items.length, (i) {
                    final it = qp.quote.items[i];
                    return LineItemRow(
                      item: it,
                      index: i,
                      onChanged: (newIt) => qp.updateItem(i, newIt),
                      onRemove: () => qp.removeItem(i),
                      canRemove: qp.quote.items.length > 1,
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Add Item Button
          _buildGradientButton(
            context: context,
            onPressed: qp.addItem,
            icon: Icons.add_circle_outline,
            label: 'Add Product/Service',
            gradientColors: [
              Theme.of(context).primaryColor.withOpacity(0.8),
              Theme.of(context).primaryColor.withOpacity(0.5),
            ],
          ),
          const SizedBox(height: 32),
          Card(
            elevation: 0,
            color: Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Subtotal (Net)'),
                  Text(formatCurrency(qp.subtotal, code: qp.quote.currencyCode)),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Tax'),
                  Text(formatCurrency(qp.totalTax, code: qp.quote.currencyCode)),
                ]),
                const SizedBox(height: 8),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(formatCurrency(qp.grandTotal, code: qp.quote.currencyCode), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00C853))),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Preview
              _buildGradientButton(
                context: context,
                icon: Icons.preview,
                label: 'Preview',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuotePreview()));
                },
                gradientColors: [Colors.purple.shade400, Colors.deepPurple.shade700],
              ),
              // Save Draft
              _buildGradientButton(
                context: context,
                icon: Icons.save,
                label: 'Save Draft',
                onPressed: () async {
                  await qp.saveQuote();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quote draft saved successfully!')));
                  }
                },
                gradientColors: [Colors.orange.shade700, Colors.deepOrange.shade900],
              ),
              // Send
              _buildGradientButton(
                context: context,
                icon: Icons.send,
                label: 'Send (Simulate)',
                onPressed: () {
                  qp.setStatus(QuoteStatus.Sent);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quote sent (simulated)')));
                },
                gradientColors: [Colors.blue.shade700, Colors.blue.shade900],
              ),
            ],
          )
        ]),
      );
    });
  }
}

/* ============================
  Widgets: QuotePreview (Styled)
  ============================ */

class QuotePreview extends StatelessWidget {
  const QuotePreview({Key? key}) : super(key: key);

  TableRow _buildItemRow(QuoteItem it, bool taxInclusive, String currencyCode) {
    final r = calculateItemTotal(it, taxInclusive: taxInclusive);
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
      children: [
        TableCell(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.name.isEmpty ? '-' : it.name, style: const TextStyle(color: Colors.black87)),
                  Text(
                    'Tax: ${it.taxPct.toStringAsFixed(0)}% | Discount: ${formatCurrency(it.discount * it.qty, code: currencyCode)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            )),
        TableCell(
            child: Text(it.qty.toStringAsFixed(it.qty.truncateToDouble() == it.qty ? 0 : 2),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87))),
        TableCell(
            child: Text(formatCurrency(it.rate, code: currencyCode),
                textAlign: TextAlign.right, style: const TextStyle(color: Colors.black87))),
        TableCell(
            child: Text(formatCurrency(r.total, code: currencyCode),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF00C853)))),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, Color color, String currencyCode, {bool isGrandTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isGrandTotal ? 18 : 14,
              fontWeight: isGrandTotal ? FontWeight.w900 : FontWeight.normal,
              color: isGrandTotal ? Colors.black : Colors.black54,
            ),
          ),
          Text(
            formatCurrency(amount, code: currencyCode),
            style: TextStyle(
              fontSize: isGrandTotal ? 18 : 14,
              fontWeight: isGrandTotal ? FontWeight.w900 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QuoteProvider>(context, listen: false);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Quote Preview (Print Layout)')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800), // Max width for print layout
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: Colors.white, // White background for print-like preview
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header (Your Company & Quote Details)
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('QUOTIFY PRO SOLUTIONS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: theme.primaryColor, letterSpacing: 1.2)),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Quote: ${qp.quote.reference.isEmpty ? 'N/A' : qp.quote.reference}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    Text('Date: ${DateFormat('dd MMM, yyyy').format(DateTime.now())}', style: const TextStyle(color: Colors.grey)),
                  ]),
                ]),
                const Divider(color: Colors.black, thickness: 1.5),
                const SizedBox(height: 16),

                // Client Details
                const Text('Bill To:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                Text(qp.quote.clientName.isEmpty ? 'N/A' : qp.quote.clientName, style: const TextStyle(color: Colors.black87)),
                Text(qp.quote.clientAddress.isEmpty ? 'N/A' : qp.quote.clientAddress, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 24),

                // Itemized List Table
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(4),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2.5),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.15)),
                      children: const [
                        TableCell(child: Padding(padding: EdgeInsets.all(8.0), child: Text('DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)))),
                        TableCell(child: Padding(padding: EdgeInsets.all(8.0), child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)))),
                        TableCell(child: Padding(padding: EdgeInsets.all(8.0), child: Text('RATE (₹)', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)))),
                        TableCell(child: Padding(padding: EdgeInsets.all(8.0), child: Text('TOTAL (₹)', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)))),
                      ],
                    ),
                    ...qp.quote.items.map((it) => _buildItemRow(it, qp.quote.taxInclusive, qp.quote.currencyCode)).toList(),
                  ],
                ),
                const SizedBox(height: 32),

                // Totals Summary
                Container(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        _buildTotalRow('Subtotal (Net)', qp.subtotal, Colors.black87, qp.quote.currencyCode),
                        _buildTotalRow('Total Tax', qp.totalTax, Colors.orange.shade800, qp.quote.currencyCode),
                        const Divider(color: Colors.black, thickness: 2),
                        _buildTotalRow('GRAND TOTAL', qp.grandTotal, theme.primaryColor, qp.quote.currencyCode, isGrandTotal: true),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Terms: Payment required within 30 days.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Print / Save PDF'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print action (simulated)')));
                    },
                  )
                ])
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================
  Main app and layout
  ============================ */

class ProductQuoteApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Theme definition from v2
    const MaterialColor primaryBlue = MaterialColor(
      0xFF1A73E8, // Primary 500 color (Google Blue-like)
      <int, Color>{
        50: Color(0xFFE8F0FE),
        100: Color(0xFFCCE0FD),
        200: Color(0xFF99C2FB),
        300: Color(0xFF66A3F9),
        400: Color(0xFF3385F9),
        500: Color(0xFF1A73E8),
        600: Color(0xFF1669D4),
        700: Color(0xFF135AB9),
        800: Color(0xFF0F4C9B),
        900: Color(0xFF0C3D7F),
      },
    );

    return ChangeNotifierProvider(
      create: (_) => QuoteProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Quotify Pro Elite',
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: Brightness.dark,
          primarySwatch: primaryBlue,
          colorScheme: ColorScheme.dark(
            primary: primaryBlue,
            secondary: const Color(0xFF00C853), // Vibrant green
            background: const Color(0xFF1A1A2E), // Deep dark background
            surface: const Color(0xFF232946), // Slightly lighter surface for cards
          ),
          scaffoldBackgroundColor: const Color(0xFF121212), // Even darker for contrast
          cardColor: const Color(0xFF1A1A2E), // Base color for glassmorphism
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF232946).withOpacity(0.6), // Transparent dark blue
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: primaryBlue[300]!, width: 2), // Highlight on focus
            ),
            labelStyle: TextStyle(color: Colors.grey[400]),
            hintStyle: TextStyle(color: Colors.grey[600]),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          ),
          // Gradient buttons styling is handled by the _buildGradientButton helper function
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              elevation: 0, // Elevation handled by custom container/shadow
            ),
          ),
        ),
        home: const QuoteHomeScreen(),
      ),
    );
  }
}

class QuoteHomeScreen extends StatelessWidget {
  const QuoteHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotify Pro Elite - Builder', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 0.8)),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth > 1000) {
          return Row(
            children: [
              const Expanded(flex: 2, child: QuoteForm()),
              const VerticalDivider(width: 1),
              // Quick Preview Section
              Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Consumer<QuoteProvider>(builder: (c, qp, _) {
                      if (qp.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Quick Preview', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        _buildGlassmorphicCard(
                          context,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Client: ${qp.quote.clientName.isEmpty ? 'N/A' : qp.quote.clientName}'),
                              const SizedBox(height: 8),
                              Text('Items: ${qp.quote.items.length}'),
                              const SizedBox(height: 8),
                              Text('Subtotal: ${formatCurrency(qp.subtotal, code: qp.quote.currencyCode)}'),
                              const SizedBox(height: 8),
                              Text('Grand Total: ${formatCurrency(qp.grandTotal, code: qp.quote.currencyCode)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00C853))),
                              const SizedBox(height: 12),
                              // Open Preview Button
                              _buildGradientButton(
                                context: context,
                                icon: Icons.open_in_new,
                                label: 'Open Full Preview',
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuotePreview()));
                                },
                                gradientColors: [Colors.purple.shade400, Colors.deepPurple.shade700],
                              ),
                            ]),
                          ),
                        )
                      ]);
                    }),
                  ))
            ],
          );
        }
        // Mobile view
        return const QuoteForm();
      }),
    );
  }
}

void main() {
  runApp(ProductQuoteApp());
}