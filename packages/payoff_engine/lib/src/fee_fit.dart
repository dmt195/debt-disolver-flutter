/// The largest amount up to [max] that fits in [room] together with its fee.
/// The amount plus its fee rises with the amount, so a binary search finds it.
int largestFittingAmount(int room, int max, int Function(int) fee) {
  var low = 0;
  var high = max;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (mid + fee(mid) <= room) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}
